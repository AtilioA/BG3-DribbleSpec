import json

import pytest

from dribblespec_mutate import run
from dribblespec_mutate.run import (MAX_EXPRESSION, AgentError, ConsoleAgent, EvalOutcomeUnknown, decode_result,
                                    lua_str, run_plan, summarize)

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
        self.tests = ["t", "u"]
        self.coverage = {"t": [1, 2], "u": []}
        self.duration_ms = 1
        self.gen = 1

    def _append(self, name, record):
        with open(self.dir / name, "a", encoding="utf-8") as f:
            f.write(json.dumps(record) + "\n")

    def generation(self):
        return self.gen

    def prepare(self, run_id):
        self.calls.append("Prepare")
        (self.dir / "tests.json").write_text(json.dumps(self.tests))
        return self.statuses["Prepare"]

    def dry_run(self, run_id, test_ids):
        self.calls.append(f"DryRun {test_ids}")
        for test in test_ids:
            if test in self.coverage:
                self._append("coverage.jsonl", {"test": test, "status": "passed", "durationMs": self.duration_ms,
                                                "steps": 3, "hits": self.coverage[test]})
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
    assert agent.calls == ["Prepare", "DryRun ['t']", "DryRun ['u']", "RunMutant 1 ['t']", "RunMutant 2 ['t']",
                           "Restore"]
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


def test_a_restore_eval_failure_keeps_the_original_error(tmp_path):
    class NotReady(FakeAgent):
        def restore(self, run_id):
            raise AgentError("Restore eval failed: not_ready")

    agent = NotReady(tmp_path, dry_run_status="error: test failed in dry run: t")
    with pytest.raises(AgentError, match="test failed in dry run: t.*Restore eval failed: not_ready"):
        run_plan(PLAN, {}, tmp_path, agent)


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


class LateLine(FakeAgent):
    """Mutant 1's eval (or DryRun of `u`) misses its deadline; its line appears on the `line_at`-th later status read."""

    def __init__(self, root, line_at=2, gen_change_at=None, late_dry_run=False, truncate=False):
        super().__init__(root)
        self.truncate = truncate
        self.line_at, self.gen_change_at, self.late_dry_run = line_at, gen_change_at, late_dry_run
        self.pending, self.reads = None, 0

    def generation(self):
        if self.pending:
            self.reads += 1
            if self.reads == self.gen_change_at:
                self.gen = 2
            if self.reads == self.line_at:
                self.calls.append(f"line {self.pending}")
                if self.pending == "u":
                    self._append("coverage.jsonl", {"test": "u", "status": "passed", "durationMs": 1, "steps": 0,
                                                    "hits": []})
                else:
                    self._append("results.jsonl", {"mutantId": 1, "status": "Killed", "killedBy": ["t"],
                                                   "passed": 0, "failed": 1, "skipped": 0, "durationMs": 1,
                                                   "attempt": 1})
                self.pending = None
        return self.gen

    def dry_run(self, run_id, test_ids):
        if not (self.late_dry_run and test_ids == ["u"]):
            return super().dry_run(run_id, test_ids)
        self.calls.append(f"DryRun {test_ids}")
        self.pending = "u"
        raise EvalOutcomeUnknown("DryRun eval outcome unknown: backend_attach_timeout")

    def run_mutant(self, run_id, mutant_id, test_ids):
        if mutant_id != 1 or self.late_dry_run:
            return super().run_mutant(run_id, mutant_id, test_ids)
        self.calls.append(f"RunMutant 1 {test_ids}")
        if self.truncate:
            with open(self.dir / "results.jsonl", "a") as f:
                f.write('{"mutantId": 1, "sta')
        self.pending = 1
        raise EvalOutcomeUnknown("RunMutant eval outcome unknown: backend_attach_timeout")


@pytest.fixture
def no_sleep(monkeypatch):
    monkeypatch.setattr(run.time, "sleep", lambda _s: None)


def test_a_late_line_after_a_missed_deadline_keeps_the_agent_status(tmp_path, no_sleep):
    agent = LateLine(tmp_path)
    results = run_plan(PLAN, {}, tmp_path, agent)

    assert results[1]["status"] == "Killed"
    assert agent.calls[-4:] == ["RunMutant 1 ['t']", "line 1", "RunMutant 2 ['t']", "Restore"]


def test_a_late_coverage_line_after_a_missed_dry_run_deadline_continues_the_run(tmp_path, no_sleep):
    agent = LateLine(tmp_path, late_dry_run=True)
    run_plan(PLAN, {}, tmp_path, agent)
    assert agent.calls[:5] == ["Prepare", "DryRun ['t']", "DryRun ['u']", "line u", "RunMutant 1 ['t']"]


def test_no_line_past_the_wait_bound_records_timeout_and_stops_without_restore(tmp_path, no_sleep, monkeypatch):
    monkeypatch.setattr(run, "LATE_LINE_WAIT_S", 0)
    agent = LateLine(tmp_path, line_at=None, truncate=True)
    with pytest.raises(AgentError, match="dribblespec-mutate resume r1"):
        run_plan(PLAN, {}, tmp_path, agent)

    lines = run.read_jsonl(tmp_path / "DribbleSpecMutation/r1/results.jsonl")
    assert lines[-1]["mutantId"] == 1 and lines[-1]["status"] == "Timeout"
    assert agent.calls[-1] == "RunMutant 1 ['t']"


def test_the_wait_bound_counts_from_the_send_time(tmp_path, no_sleep, monkeypatch):
    clock = iter(range(0, 1000, 30))
    monkeypatch.setattr(run.time, "monotonic", lambda: next(clock))
    agent = LateLine(tmp_path, line_at=None)
    with pytest.raises(AgentError, match=r"no line after the eval deadline \(game hung or batch failed\)"):
        run_plan(PLAN, {}, tmp_path, agent)
    # Sent at 0; reads at 30 and 60 reach the 60 s bound.
    assert agent.reads == 2


def test_a_truncated_tail_is_replaced_by_the_host_timeout_line(tmp_path, no_sleep, monkeypatch):
    monkeypatch.setattr(run, "LATE_LINE_WAIT_S", 0)
    with pytest.raises(AgentError):
        run_plan(PLAN, {}, tmp_path, LateLine(tmp_path, line_at=None, truncate=True))

    text = (tmp_path / "DribbleSpecMutation/r1/results.jsonl").read_text()
    assert '{"mutantId": 1, "sta{' not in text and '"sta\n' not in text
    assert text.endswith("\n") and json.loads(text.splitlines()[-1])["status"] == "Timeout"


def test_a_corrupt_middle_line_is_a_clear_error(tmp_path):
    path = tmp_path / "r.jsonl"
    path.write_text('{"a": 1}\n{"mutantId": 2, "sta\n{"b": 2}\n')
    with pytest.raises(AgentError, match="line 2 is not valid JSON"):
        run.read_jsonl(path)


def test_a_generation_change_while_a_line_is_pending_stops_the_run(tmp_path, no_sleep):
    agent = LateLine(tmp_path, line_at=None, gen_change_at=3)
    with pytest.raises(AgentError, match="context generation changed.*resume"):
        run_plan(PLAN, {}, tmp_path, agent)
    assert "RunMutant 2 ['t']" not in agent.calls


def test_a_generation_change_before_a_call_stops_the_run(tmp_path):
    class Restarted(FakeAgent):
        def run_mutant(self, run_id, mutant_id, test_ids):
            self.gen = 2
            return super().run_mutant(run_id, mutant_id, test_ids)

    agent = Restarted(tmp_path)
    with pytest.raises(AgentError, match="context generation changed"):
        run_plan(PLAN, {}, tmp_path, agent)
    assert agent.calls[-2:] == ["RunMutant 1 ['t']", "Restore"]


def test_dry_run_batches_start_with_one_test_and_grow_from_measured_durations(tmp_path):
    agent = FakeAgent(tmp_path)
    agent.tests = ["a", "b", "c", "d"]
    agent.coverage = {t: [1] for t in agent.tests}
    agent.duration_ms = 4000
    run_plan(PLAN, {}, tmp_path, agent)
    assert [c for c in agent.calls if c.startswith("DryRun")] == ["DryRun ['a']", "DryRun ['b', 'c']", "DryRun ['d']"]


def test_dry_run_batches_stay_at_one_test_until_a_duration_exists(tmp_path):
    agent = FakeAgent(tmp_path)
    agent.tests = ["a", "b", "c"]
    agent.coverage = {"c": [1]}
    run_plan(PLAN, {}, tmp_path, agent)
    assert [c for c in agent.calls if c.startswith("DryRun")] == ["DryRun ['a']", "DryRun ['b']", "DryRun ['c']"]


def test_the_generation_baseline_is_read_after_prepare(tmp_path):
    class Reattached(FakeAgent):
        def prepare(self, run_id):
            self.gen = 2
            return super().prepare(run_id)

    assert run_plan(PLAN, {}, tmp_path, Reattached(tmp_path))[2]["status"] == "Killed"


def test_dry_run_batches_stay_under_the_console_limit(tmp_path):
    agent = FakeAgent(tmp_path)
    agent.tests = ["x" * 17000, "y" * 17000, "z" * 17000]
    agent.coverage = {agent.tests[0]: [1]}
    run_plan(PLAN, {}, tmp_path, agent)
    assert len([c for c in agent.calls if c.startswith("DryRun")]) == 3


def test_no_passed_test_after_the_last_batch_stops_the_run(tmp_path):
    agent = FakeAgent(tmp_path)
    agent.coverage = {}
    with pytest.raises(AgentError, match="no test left after dropping skipped tests"):
        run_plan(PLAN, {}, tmp_path, agent)
    assert agent.calls == ["Prepare", "DryRun ['t']", "DryRun ['u']", "Restore"]


def test_a_broker_disconnect_is_a_clear_agent_error():
    class Disconnected(Exception):
        pass

    class Loop:
        def run(self, coro):
            coro.close()
            raise Disconnected("owner dropped the connection")

    class Session:
        async def eval(self, *args):
            pass

    agent = ConsoleAgent.__new__(ConsoleAgent)
    agent._loop, agent._session, agent._broker_disconnected = Loop(), Session(), Disconnected
    with pytest.raises(AgentError, match="Restore: broker disconnected: owner dropped the connection"):
        agent.restore("r1")


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
