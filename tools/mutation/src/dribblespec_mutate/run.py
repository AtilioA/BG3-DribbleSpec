"""`run`: drive the in-game agent over a plan and summarize the mutant statuses."""

import asyncio
import json
import os
import time
from collections import Counter
from dataclasses import dataclass
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
RESET_WAIT_S = 60.0  # after a reset, until the mutation agent is loaded again
RESET_POLL_S = 0.1


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
    def checkpoint(self, run_id: str, sets: list[tuple[int, tuple[str, ...]]]) -> str: ...
    def run_mutant(self, run_id: str, mutant_id: int, test_ids: list[str], attempt: int) -> str: ...
    def restore(self, run_id: str) -> str: ...
    def reset(self) -> None:
        """Reset the server Lua context and return once it is available at a new generation."""


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


def lua_set(index: int, tests: tuple[str, ...]) -> str:
    return f"{{ set = {index}, tests = {lua_list(list(tests))} }}"


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

    def checkpoint(self, run_id: str, sets: list[tuple[int, tuple[str, ...]]]) -> str:
        return self._call("Checkpoint", f"{lua_str(run_id)}, {{{', '.join(lua_set(i, t) for i, t in sets)}}}")

    def run_mutant(self, run_id: str, mutant_id: int, test_ids: list[str], attempt: int) -> str:
        return self._call("RunMutant", f"{lua_str(run_id)}, {mutant_id}, {lua_list(test_ids)}, {attempt}")

    def restore(self, run_id: str) -> str:
        return self._call("Restore", lua_str(run_id))

    def reset(self) -> None:
        response = self._run("reset", self._session.reset("server", EVAL_DEADLINE_S))
        server = next((c for c in response.contexts if c.context == "server"), None)
        if response.outcome != "succeeded" or server is None or server.new_generation is None:
            error = f"{response.error.code}: {response.error.message}" if response.error else response.outcome
            raise AgentError(f"server reset failed: {error}")
        deadline = time.monotonic() + RESET_WAIT_S
        # Remove this check when the debugger reports mod load completion.
        while True:
            probe = self._run("eval", self._session.eval("server", "Mods.Dribbles ~= nil and Mods.Dribbles.Mutation ~= nil", 5))
            if probe.outcome == "succeeded" and probe.result == "true":
                return
            if time.monotonic() >= deadline:
                raise AgentError(f"the mutation agent was not loaded {RESET_WAIT_S:.0f} s after a server reset")
            time.sleep(RESET_POLL_S)


def se_user_root() -> Path:
    return Path(os.environ["LOCALAPPDATA"]) / "Larian Studios" / "Baldur's Gate 3" / "Script Extender"


def read_jsonl(path: Path, offset: int = 0) -> list[dict]:
    """Parse one JSON object per line from byte `offset`; a truncated last line is ignored."""
    if not path.exists():
        return []
    with open(path, "rb") as f:
        f.seek(offset)
        text = f.read().decode("utf-8")
    lines = [line for line in text.splitlines() if line.strip()]
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


class GenerationChanged(Exception):
    """The server Lua context generation changed while a line was pending."""


@dataclass
class _Run:
    plan: dict
    dir: Path
    agent: Agent
    generation: int | None = None

    @property
    def id(self) -> str:
        return self.plan["runId"]

    def arm(self) -> None:
        """Restore, then Prepare: after a reattach Restore removes the kept patches; after a reset it is a no-op."""
        _check("Restore", self.agent.restore(self.id))
        _check("Prepare", self.agent.prepare(self.id))
        self.generation = self.agent.generation()

    def generation_changed(self) -> bool:
        current = self.agent.generation()
        return current is not None and current != self.generation

    def before_call(self) -> None:
        if self.generation_changed():
            self.arm()

    def recover(self) -> None:
        self.agent.reset()
        self.arm()


def _size(path: Path) -> int:
    return path.stat().st_size if path.exists() else 0


def _wait_for_line(run: _Run, path: Path, offset: int, found: Callable[[dict], bool], sent: float) -> bool:
    """After an unknown eval outcome, poll `path` past `offset` until a line matches; False past the bound."""
    while True:
        if run.generation_changed():
            raise GenerationChanged
        if any(found(r) for r in read_jsonl(path, offset)):
            return True
        if time.monotonic() - sent >= LATE_LINE_WAIT_S:
            return False
        time.sleep(LATE_LINE_POLL_S)


def _append_timeout(path: Path, mutant_id: int, attempt: int) -> None:
    # Drop a partial agent line so the host line starts on a line of its own.
    data = path.read_bytes() if path.exists() else b""
    with open(path, "wb") as f:
        f.write(data[:data.rfind(b"\n") + 1])
        line = _host_result(mutant_id, "Timeout", "no result line after the eval deadline") | {"attempt": attempt}
        f.write((json.dumps(line) + "\n").encode("utf-8"))


def _send_batched(run: _Run, name: str, items: list, item_text: Callable[[object], str],
                  send: Callable[[list], str], path: Path, is_last: Callable[[dict, object], bool]) -> None:
    """Send `items` in batches: one first, then as many as fit the measured mean duration and the console limit.

    A batch pending across a generation change is sent again once, after re-arming.
    """
    start = 0
    size = 1
    resent = False
    while start < len(items):
        batch = [items[start]]
        length = CALL_OVERHEAD + len(item_text(items[start]))
        while len(batch) < size and start + len(batch) < len(items):
            item = len(item_text(items[start + len(batch)])) + 2  # ", " separator
            if length + item > MAX_EXPRESSION:
                break
            length += item
            batch.append(items[start + len(batch)])
        run.before_call()
        offset, sent = _size(path), time.monotonic()
        try:
            _check(name, send(batch))
        except EvalOutcomeUnknown:
            last = batch[-1]
            try:
                if not _wait_for_line(run, path, offset, lambda r: is_last(r, last), sent):
                    raise GameUnresponsive(f"{name}: no line after the eval deadline (game hung or batch failed); {_resume_hint(run.id)}")
            except GenerationChanged:
                if resent:
                    raise GameUnresponsive(f"{name}: the context generation changed again while a line was pending; {_resume_hint(run.id)}") from None
                run.arm()
                resent = True
                continue
        start += len(batch)
        resent = False
        durations = [r["durationMs"] for r in read_jsonl(path)]
        if durations:
            size = max(1, int(DRY_RUN_BATCH_MS // max(sum(durations) / len(durations), 1)))


def _dry_run(run: _Run, test_ids: list[str]) -> list[dict]:
    """Dry run every test, print the skipped count per reason, and return the passed tests' coverage."""
    path = run.dir / "coverage.jsonl"
    _send_batched(run, "DryRun", test_ids, lua_str, lambda batch: run.agent.dry_run(run.id, batch), path,
                  lambda c, last: c["test"] == last)
    # A batch sent again after a generation change repeats its lines; the last line per test wins.
    coverage = list({c["test"]: c for c in read_jsonl(path)}.values())
    skipped = Counter(c["skipReason"] for c in coverage if c["status"] == "skipped")
    if skipped:
        print(f"Skipped at baseline: {skipped.total()}")
        for reason, count in skipped.most_common():
            print(f"  {count} {reason.encode('ascii', 'backslashreplace').decode()}")
    passed = [c for c in coverage if c["status"] == "passed"]
    if not passed:
        raise AgentError("DryRun: no test left after dropping skipped tests")
    return passed


def _check_sets(run: _Run, sets: list[tuple[str, ...]]) -> dict[tuple[str, ...], bool]:
    """Run each set with no mutant; return whether it passed. Set indexes continue after those in checkpoint.jsonl."""
    path = run.dir / "checkpoint.jsonl"
    first = max((r["set"] for r in read_jsonl(path)), default=0) + 1
    indexed = list(enumerate(sets, start=first))
    _send_batched(run, "Checkpoint", indexed, lambda s: lua_set(*s), lambda batch: run.agent.checkpoint(run.id, batch),
                  path, lambda r, last: r["set"] == last[0])
    status = {r["set"]: r["status"] for r in read_jsonl(path)}
    return {tests: status.get(index) == "passed" for index, tests in indexed}


def _checkpoint(run: _Run, covering: dict[int, list[str]]) -> set[str]:
    """Run each distinct covering set with no mutant; exclude every test of a failing set until all sets pass."""
    excluded: set[str] = set()
    passed: set[tuple[str, ...]] = set()
    while True:
        pending = list(dict.fromkeys(tuple(t for t in tests if t not in excluded) for tests in covering.values()))
        pending = [s for s in pending if s and s not in passed]
        if not pending:
            break
        for tests, ok in _check_sets(run, pending).items():
            if ok:
                passed.add(tests)
            else:
                excluded.update(tests)
    if covering and all(set(tests) <= excluded for tests in covering.values()):
        raise AgentError("every covering test failed the baseline checkpoint")
    (run.dir / "excluded.json").write_text(json.dumps(sorted(excluded)), encoding="utf-8")
    return excluded


def _run_mutant(run: _Run, mutant_id: int, tests: list[str], attempt: int) -> tuple[str, int]:
    """Run one mutant and return its status and attempt; a generation change while its line is pending re-runs it once as attempt 2."""
    path = run.dir / "results.jsonl"
    while True:
        run.before_call()
        offset, sent = _size(path), time.monotonic()
        try:
            _check(f"RunMutant {mutant_id}", run.agent.run_mutant(run.id, mutant_id, tests, attempt))
        except EvalOutcomeUnknown:
            try:
                found = _wait_for_line(run, path, offset, lambda r: r.get("mutantId") == mutant_id, sent)
            except GenerationChanged:
                if attempt == 2:
                    raise GameUnresponsive(f"RunMutant {mutant_id}: the context generation changed again while a line was pending; {_resume_hint(run.id)}") from None
                run.arm()
                attempt = 2
                continue
            if not found:
                _append_timeout(path, mutant_id, attempt)
                raise GameUnresponsive(
                    f"RunMutant {mutant_id}: no line after the eval deadline (game hung or batch failed); {_resume_hint(run.id)}") from None
        lines = [r for r in read_jsonl(path, offset) if r.get("mutantId") == mutant_id]
        if not lines:
            raise AgentError(f"RunMutant {mutant_id}: no result line")
        return lines[-1]["status"], attempt


def _run_mutants(run: _Run, covering: dict[int, list[str]]) -> None:
    """Run each covered mutant; after each file, checkpoint the sets used since the last pass and recover on failure."""
    by_file: dict[int, list[int]] = {}
    for m in run.plan["mutants"]:
        if covering.get(m["id"]):
            by_file.setdefault(m["file"], []).append(m["id"])
    for ids in by_file.values():
        killed = []
        for mutant_id in ids:
            tests = covering[mutant_id]
            status, attempt = _run_mutant(run, mutant_id, tests, 1)
            if status == "RuntimeError" and attempt == 1 and not _check_sets(run, [tuple(tests)])[tuple(tests)]:
                run.recover()
                _run_mutant(run, mutant_id, tests, 2)
                for killed_id in killed:
                    _run_mutant(run, killed_id, covering[killed_id], 2)
                killed = []
            elif status == "Killed" and attempt == 1:
                killed.append(mutant_id)
        sets = list(dict.fromkeys(tuple(covering[i]) for i in ids))
        if not all(_check_sets(run, sets).values()):
            run.recover()
            for mutant_id in killed:
                _run_mutant(run, mutant_id, covering[mutant_id], 2)


def _run_agent(run: _Run) -> None:
    """Dry run, append the host-classified results, then run each covered mutant."""
    plan = run.plan
    test_ids = json.loads((run.dir / "tests.json").read_text(encoding="utf-8"))
    if not test_ids:
        raise AgentError(f"no tests match the test filter {json.dumps(plan['testFilter'])}")
    coverage = _dry_run(run, test_ids)
    covering = {m["id"]: [c["test"] for c in coverage if m["id"] in (c["hits"] or [])] for m in plan["mutants"]
                if "ignoredReason" not in m}
    excluded = _checkpoint(run, {i: t for i, t in covering.items() if t})
    with open(run.dir / "results.jsonl", "a", encoding="utf-8") as f:
        for m in plan["mutants"]:
            if "ignoredReason" in m:
                f.write(json.dumps(_host_result(m["id"], "Ignored", m["ignoredReason"])) + "\n")
            elif not covering[m["id"]]:
                f.write(json.dumps(_host_result(m["id"], "NoCoverage")) + "\n")
            elif all(t in excluded for t in covering[m["id"]]):
                f.write(json.dumps(_host_result(m["id"], "Ignored", "order-dependent tests")) + "\n")
    _run_mutants(run, {i: [t for t in tests if t not in excluded] for i, tests in covering.items()})


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
        _run_agent(_Run(plan, run_dir, agent, agent.generation()))
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
