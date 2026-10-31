import json

import pytest

from dribblespec_mutate.run import MAX_EXPRESSION, AgentError, ConsoleAgent, decode_result, lua_str, run_plan, summarize

PLAN = {
    "runId": "r1", "testFilter": {"tags": ["validators"]},
    "files": [{"index": 1, "path": "F.lua", "patchPath": "DribbleSpecMutation/r1/1.lua"}],
    "mutants": [
        {"id": 1, "file": 1, "line": 3, "operator": "RelationalBoundary", "original": "<", "replacement": "<="},
        {"id": 2, "file": 1, "line": 3, "operator": "RelationalBoundary", "original": "<", "replacement": ">="},
        {"id": 3, "file": 1, "line": 9, "operator": "RelationalBoundary", "original": ">", "replacement": ">="},
        {"id": 4, "file": 1, "line": 12, "operator": "RelationalBoundary", "original": ">", "replacement": "<=",
         "ignoredReason": "static"},
    ],
}
RESULT_KEYS = {"mutantId", "status", "killedBy", "passed", "failed", "skipped", "durationMs", "attempt"}


class FakeAgent:
    """Implements the agent protocol over files: test `t` hits mutants 1 and 2 and kills mutant 2."""

    def __init__(self, root, prepare_status="ok", dry_run_status="ok", restore_status="ok"):
        self.dir = root / "DribbleSpecMutation" / "r1"
        self.statuses = {"Prepare": prepare_status, "DryRun": dry_run_status, "Restore": restore_status}
        self.calls = []

    def _append(self, name, record):
        with open(self.dir / name, "a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")

    def prepare(self, run_id):
        self.calls.append("Prepare")
        (self.dir / "tests.json").write_text(json.dumps(["t", "u"]))
        return self.statuses["Prepare"]

    def dry_run(self, run_id, test_ids):
        self.calls.append(f"DryRun {test_ids}")
        self._append("coverage.jsonl", {"test": "t", "status": "passed", "durationMs": 1, "steps": 3, "hits": [1, 2]})
        self._append("coverage.jsonl", {"test": "u", "status": "passed", "durationMs": 1, "steps": 0, "hits": []})
        return self.statuses["DryRun"]

    def run_mutant(self, run_id, mutant_id, test_ids):
        self.calls.append(f"RunMutant {mutant_id} {test_ids}")
        killed = mutant_id == 2
        self._append("results.jsonl", {"mutantId": mutant_id, "status": "Killed" if killed else "Survived",
                                       "killedBy": ["t"] if killed else [], "passed": 0 if killed else 1,
                                       "failed": 1 if killed else 0, "skipped": 0, "durationMs": 1, "attempt": 1})
        return "ok"

    def restore(self, run_id):
        self.calls.append("Restore")
        return self.statuses["Restore"]


def test_run_classifies_each_mutant_and_restores(tmp_path):
    agent = FakeAgent(tmp_path)
    results = run_plan(PLAN, {"DribbleSpecMutation/r1/1.lua": "chunk"}, tmp_path, agent)

    assert {i: r["status"] for i, r in results.items()} == {1: "Survived", 2: "Killed", 3: "NoCoverage", 4: "Ignored"}
    assert results[2]["killedBy"] == ["t"]
    assert agent.calls == ["Prepare", "DryRun ['t', 'u']", "RunMutant 1 ['t']", "RunMutant 2 ['t']", "Restore"]
    assert (tmp_path / "DribbleSpecMutation/r1/1.lua").read_text() == "chunk"
    assert json.loads((tmp_path / "DribbleSpecMutation/r1/plan.json").read_text())["runId"] == "r1"


def test_results_file_has_a_full_line_for_every_mutant_including_host_statuses(tmp_path):
    run_plan(PLAN, {}, tmp_path, FakeAgent(tmp_path))
    lines = [json.loads(line) for line in (tmp_path / "DribbleSpecMutation/r1/results.jsonl").read_text().splitlines()]

    assert all(RESULT_KEYS <= set(line) for line in lines)
    assert {line["mutantId"]: line["status"] for line in lines} == {1: "Survived", 2: "Killed", 3: "NoCoverage",
                                                                    4: "Ignored"}
    # Host lines are appended after DryRun, before the agent's RunMutant lines.
    assert [line["mutantId"] for line in lines] == [3, 4, 1, 2]
    assert lines[1] == {"mutantId": 4, "status": "Ignored", "message": "static", "killedBy": [], "passed": 0,
                         "failed": 0, "skipped": 0, "durationMs": 0, "attempt": 1}


def test_summary_lists_counts_score_filter_ignored_ratio_and_survivors(tmp_path):
    results = run_plan(PLAN, {}, tmp_path, FakeAgent(tmp_path))
    summary = summarize(PLAN, results).splitlines()

    assert "Killed 1, Survived 1, NoCoverage 1, Timeout 0, RuntimeError 0, Ignored 1" in summary
    assert "F.lua: 1 of 4 ignored" in summary
    assert "Score: 50.0%" in summary
    assert 'Test filter: {"tags": ["validators"]}' in summary
    assert summary[-1] == "  F.lua:3 RelationalBoundary < -> <="


def test_prepare_error_stops_the_run_before_any_test(tmp_path):
    agent = FakeAgent(tmp_path, prepare_status="error: deployed source differs from repo: F.lua")
    with pytest.raises(AgentError, match="deployed source differs from repo: F.lua"):
        run_plan(PLAN, {}, tmp_path, agent)
    assert agent.calls == ["Prepare"]


def test_dry_run_error_still_restores(tmp_path):
    agent = FakeAgent(tmp_path, dry_run_status="error: test failed in dry run: t")
    with pytest.raises(AgentError, match="test failed in dry run: t"):
        run_plan(PLAN, {}, tmp_path, agent)
    assert agent.calls[-1] == "Restore"


def test_restore_error_keeps_the_original_error(tmp_path):
    agent = FakeAgent(tmp_path, dry_run_status="error: test failed in dry run: t", restore_status="error: boom")
    with pytest.raises(AgentError, match="test failed in dry run: t") as info:
        run_plan(PLAN, {}, tmp_path, agent)
    assert "Restore: error: boom" in str(info.value)


def test_last_result_line_wins_and_a_truncated_last_line_is_ignored(tmp_path):
    class Rerun(FakeAgent):
        def run_mutant(self, run_id, mutant_id, test_ids):
            super().run_mutant(run_id, mutant_id, test_ids)
            if mutant_id == 2:
                self._append("results.jsonl", {"mutantId": 1, "status": "Killed", "killedBy": ["t"], "attempt": 2})
                with open(self.dir / "results.jsonl", "a") as f:
                    f.write('{"mutantId": 2, "sta')
            return "ok"

    results = run_plan(PLAN, {}, tmp_path, Rerun(tmp_path))
    assert (results[1]["status"], results[1]["attempt"]) == ("Killed", 2)
    assert results[2]["status"] == "Killed"


@pytest.mark.parametrize("value", ['Suite "quoted" \\ name', "line\nbreak\ttab", "caf\u00e9"])
def test_lua_str_round_trips_through_lua(lua, value):
    assert lua.eval(lua_str(value)) == value


def test_decode_result_reads_the_json_the_eval_returns():
    # The broker shows a string result as the raw text in double quotes, without escaping.
    assert decode_result('"["error: \\"x\\"\\nnext"]"') == 'error: "x"\nnext'


def test_an_eval_over_the_input_limit_fails_before_sending():
    agent = ConsoleAgent.__new__(ConsoleAgent)
    with pytest.raises(AgentError, match="DryRun call is .* characters; the console limit is 32768"):
        agent.dry_run("r1", ["t" * MAX_EXPRESSION])
