"""`run`: drive the in-game agent over a plan and summarize the mutant statuses."""

import asyncio
import json
import os
import time
from pathlib import Path
from typing import Callable, Protocol

from . import build_plan, format_mutant, ignored_per_file, load_config, next_run_id

STATUSES = ("Killed", "Survived", "NoCoverage", "Timeout", "RuntimeError", "Ignored")
EVAL_DEADLINE_S = 25.0
MAX_EXPRESSION = 32768  # bg3se_console eval input limit


LATE_LINE_WAIT_S = 60.0  # from the call's send time: the 25 s eval deadline, the agent's 20 s wall clock, margin
LATE_LINE_POLL_S = 1.0
DRY_RUN_BATCH_MS = 10000
CALL_OVERHEAD = 200  # characters of an eval around its test id list


class AgentError(Exception):
    pass


class EvalOutcomeUnknown(AgentError):
    """The eval may have run in game, but its result never came back (for example, a missed deadline)."""


class GameUnresponsive(AgentError):
    """No line arrived within the wait bound; the game may be hung, so no further call is sent."""


class Agent(Protocol):
    """The `Mods.Dribbles.Mutation` calls; each returns the agent's status string."""

    def generation(self) -> int | None: ...
    def prepare(self, run_id: str) -> str: ...
    def dry_run(self, run_id: str, test_ids: list[str]) -> str: ...
    def run_mutant(self, run_id: str, mutant_id: int, test_ids: list[str]) -> str: ...
    def restore(self, run_id: str) -> str: ...


def lua_str(value: str) -> str:
    """Quote `value` as a Lua string literal; control and non-ASCII bytes become decimal escapes."""
    out = []
    for b in value.encode("utf-8"):
        if b in (0x22, 0x5C):
            out.append("\\" + chr(b))
        elif b < 0x20 or b >= 0x7F:
            out.append(f"\\{b:03d}")
        else:
            out.append(chr(b))
    return '"' + "".join(out) + '"'


def lua_list(values: list[str]) -> str:
    return "{" + ", ".join(lua_str(v) for v in values) + "}"


def decode_result(result: str) -> str:
    """Decode an eval of `Ext.Json.Stringify({ status })`.

    The broker shows a string result as its raw text in double quotes, without escaping.
    """
    if len(result) < 2 or result[0] != '"' or result[-1] != '"':
        raise AgentError(f"unexpected eval result: {result}")
    return json.loads(result[1:-1])[0]


class ConsoleAgent:
    """Agent calls sent as server evals through the shared BG3SE console broker."""

    def __init__(self):
        try:
            from bg3se_console.broker import BrokerDisconnected
            from bg3se_console.core import AgentRuntime
            from bg3se_console.mcp import SharedRuntimeSession
        except ImportError:
            raise AgentError("bg3se_console is not installed; run `uv pip install -e "
                             "C:/Users/AAD/Git/llm-skills/.agents/skills/bg3se-console-ops/bg3se-console-mcp`") from None
        self._broker_disconnected = BrokerDisconnected
        self._loop = asyncio.Runner()
        self._session = SharedRuntimeSession(AgentRuntime)
        self._loop.run(self._session.start())

    def close(self) -> None:
        try:
            self._loop.run(self._session.close())
        finally:
            self._loop.close()

    def _run(self, name: str, coro):
        try:
            return self._loop.run(coro)
        except self._broker_disconnected as e:
            raise AgentError(f"{name}: broker disconnected: {e}") from None

    def generation(self) -> int | None:
        return self._run("status", self._session.status()).contexts.server.generation

    def _call(self, name: str, args: str) -> str:
        expression = f"Ext.Json.Stringify({{ Mods.Dribbles.Mutation.{name}({args}) }})"
        if len(expression) > MAX_EXPRESSION:
            raise AgentError(f"{name} call is {len(expression)} characters; the console limit is {MAX_EXPRESSION}")
        response = self._run(name, self._session.eval("server", expression, EVAL_DEADLINE_S))
        if response.outcome != "succeeded":
            error = f"{response.error.code}: {response.error.message}" if response.error else response.outcome
            if response.outcome == "unknown":
                raise EvalOutcomeUnknown(f"{name} eval outcome unknown: {error}")
            raise AgentError(f"{name} eval failed: {error}")
        return decode_result(response.result or "")

    def prepare(self, run_id: str) -> str:
        return self._call("Prepare", lua_str(run_id))

    def dry_run(self, run_id: str, test_ids: list[str]) -> str:
        return self._call("DryRun", f"{lua_str(run_id)}, {lua_list(test_ids)}")

    def run_mutant(self, run_id: str, mutant_id: int, test_ids: list[str]) -> str:
        return self._call("RunMutant", f"{lua_str(run_id)}, {mutant_id}, {lua_list(test_ids)}")

    def restore(self, run_id: str) -> str:
        return self._call("Restore", lua_str(run_id))


def se_user_root() -> Path:
    return Path(os.environ["LOCALAPPDATA"]) / "Larian Studios" / "Baldur's Gate 3" / "Script Extender"


def read_jsonl(path: Path) -> list[dict]:
    """Parse one JSON object per line; a truncated last line is ignored."""
    if not path.exists():
        return []
    lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    records = []
    for i, line in enumerate(lines):
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            if i != len(lines) - 1:
                raise AgentError(f"{path}: line {i + 1} is not valid JSON") from None
    return records


def _check(call: str, status: str) -> None:
    if status != "ok":
        raise AgentError(f"{call}: {status}")


def _host_result(mutant_id: int, status: str, message: str | None = None) -> dict:
    result = {"mutantId": mutant_id, "status": status}
    if message is not None:
        result["message"] = message
    return result | {"killedBy": [], "passed": 0, "failed": 0, "skipped": 0, "durationMs": 0, "attempt": 1}


def _resume_hint(run_id: str) -> str:
    return f"run {run_id} stopped; resume it with `dribblespec-mutate resume {run_id}`"


def _check_generation(agent: Agent, generation: int | None, run_id: str) -> None:
    current = agent.generation()
    if current is not None and current != generation:
        raise AgentError(f"the server Lua context generation changed; {_resume_hint(run_id)}")


def _wait_for_line(path: Path, found: Callable[[dict], bool], sent: float, agent: Agent, generation: int | None,
                   run_id: str) -> bool:
    """After an unknown eval outcome, poll `path` until a line matches; False past the bound."""
    while True:
        _check_generation(agent, generation, run_id)
        if any(found(r) for r in read_jsonl(path)):
            return True
        if time.monotonic() - sent >= LATE_LINE_WAIT_S:
            return False
        time.sleep(LATE_LINE_POLL_S)


def _append_timeout(path: Path, mutant_id: int) -> None:
    # Drop a partial agent line so the host line starts on a line of its own.
    data = path.read_bytes() if path.exists() else b""
    with open(path, "wb") as f:
        f.write(data[:data.rfind(b"\n") + 1])
        f.write((json.dumps(_host_result(mutant_id, "Timeout", "no result line after the eval deadline")) + "\n")
                .encode("utf-8"))


def _dry_run(run_id: str, run_dir: Path, agent: Agent, test_ids: list[str], generation: int | None) -> list[dict]:
    """Send DryRun in batches: one test first, then as many as fit the measured mean duration and the console limit."""
    path = run_dir / "coverage.jsonl"
    start = 0
    size = 1
    while start < len(test_ids):
        batch = [test_ids[start]]
        length = CALL_OVERHEAD + len(lua_str(test_ids[start]))
        while len(batch) < size and start + len(batch) < len(test_ids):
            item = len(lua_str(test_ids[start + len(batch)])) + 2  # ", " separator
            if length + item > MAX_EXPRESSION:
                break
            length += item
            batch.append(test_ids[start + len(batch)])
        _check_generation(agent, generation, run_id)
        sent = time.monotonic()
        try:
            _check("DryRun", agent.dry_run(run_id, batch))
        except EvalOutcomeUnknown:
            last = batch[-1]
            if not _wait_for_line(path, lambda c: c["test"] == last, sent, agent, generation, run_id):
                raise GameUnresponsive(f"DryRun: no line after the eval deadline (game hung or batch failed); {_resume_hint(run_id)}")
        start += len(batch)
        durations = [c["durationMs"] for c in read_jsonl(path)]
        if durations:
            size = max(1, int(DRY_RUN_BATCH_MS // max(sum(durations) / len(durations), 1)))
    coverage = read_jsonl(path)
    if not any(c["status"] == "passed" for c in coverage):
        raise AgentError("DryRun: no test left after dropping skipped tests")
    return coverage


def _run_agent(plan: dict, run_dir: Path, agent: Agent, generation: int | None) -> None:
    """Dry run, append the host-classified results, then run each covered mutant."""
    run_id = plan["runId"]
    test_ids = json.loads((run_dir / "tests.json").read_text(encoding="utf-8"))
    if not test_ids:
        raise AgentError(f"no tests match the test filter {json.dumps(plan['testFilter'])}")
    coverage = _dry_run(run_id, run_dir, agent, test_ids, generation)
    covering = {m["id"]: [c["test"] for c in coverage if m["id"] in (c["hits"] or [])] for m in plan["mutants"]}
    with open(run_dir / "results.jsonl", "a", encoding="utf-8") as f:
        for m in plan["mutants"]:
            if "ignoredReason" in m:
                f.write(json.dumps(_host_result(m["id"], "Ignored", m["ignoredReason"])) + "\n")
            elif not covering[m["id"]]:
                f.write(json.dumps(_host_result(m["id"], "NoCoverage")) + "\n")
    for m in plan["mutants"]:
        if "ignoredReason" not in m and covering[m["id"]]:
            _check_generation(agent, generation, run_id)
            sent = time.monotonic()
            try:
                _check(f"RunMutant {m['id']}", agent.run_mutant(run_id, m["id"], covering[m["id"]]))
            except EvalOutcomeUnknown:
                path = run_dir / "results.jsonl"
                if not _wait_for_line(path, lambda r: r.get("mutantId") == m["id"], sent, agent, generation, run_id):
                    _append_timeout(path, m["id"])
                    raise GameUnresponsive(
                        f"RunMutant {m['id']}: no line after the eval deadline (game hung or batch failed); {_resume_hint(run_id)}") from None


def run_plan(plan: dict, chunks: dict[str, str], root: Path, agent: Agent) -> dict[int, dict]:
    """Write the plan under `root`, drive `agent`, and return the result per mutant id."""
    run_id = plan["runId"]
    run_dir = root / "DribbleSpecMutation" / run_id
    run_dir.mkdir(parents=True)
    for patch_path, chunk in chunks.items():
        (root / patch_path).write_text(chunk, encoding="utf-8", newline="")
    (run_dir / "plan.json").write_text(json.dumps(plan, indent=2), encoding="utf-8")

    _check("Prepare", agent.prepare(run_id))
    try:
        _run_agent(plan, run_dir, agent, agent.generation())
    except GameUnresponsive:
        raise  # the game may be hung; resume calls Restore, then Prepare
    except AgentError as e:
        try:
            status = agent.restore(run_id)
        except AgentError as restore_error:
            status = str(restore_error)
        if status != "ok":
            raise AgentError(f"{e}; Restore: {status}") from e
        raise
    _check("Restore", agent.restore(run_id))
    return {r["mutantId"]: r for r in read_jsonl(run_dir / "results.jsonl")}


def summarize(plan: dict, results: dict[int, dict]) -> str:
    lines = [f"{results[m['id']]['status']:<12} {format_mutant(plan, m)}" for m in plan["mutants"]]
    counts = {s: sum(r["status"] == s for r in results.values()) for s in STATUSES}
    lines.append(", ".join(f"{s} {n}" for s, n in counts.items()))
    lines += ignored_per_file(plan)
    detected = counts["Killed"] + counts["Timeout"]
    tested = detected + counts["Survived"]
    lines.append(f"Score: {100 * detected / tested:.1f}%" if tested else "Score: n/a (no tested mutants)")
    lines.append(f"Test filter: {json.dumps(plan['testFilter'])}")
    survivors = [m for m in plan["mutants"] if results[m["id"]]["status"] == "Survived"]
    if survivors:
        lines.append("Survivors (survived the selected tests):")
        lines += [f"  {format_mutant(plan, m)}" for m in survivors]
    return "\n".join(lines)


def cmd_run(args) -> int:
    config = load_config(Path(args.config))
    root = se_user_root()
    plan, chunks = build_plan(config, next_run_id(root))
    try:
        agent = ConsoleAgent()
        try:
            results = run_plan(plan, chunks, root, agent)
        finally:
            agent.close()
    except AgentError as e:
        print(f"error: {e}")
        return 1
    print(summarize(plan, results))
    print(f"results: {root / 'DribbleSpecMutation' / plan['runId'] / 'results.jsonl'}")
    return 0
