"""dribblespec-mutate: mutation testing host for DribbleSpec."""

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path

from .instrument import SourceError, instrument


class ConfigError(Exception):
    pass


@dataclass
class Config:
    dir: Path
    modTable: str
    modDirectory: str
    ownerModuleUUID: str
    luaRoot: str
    files: list[str]
    testFilter: dict
    ignoreCalls: list[str]


def load_config(path: Path) -> Config:
    data = json.loads(path.read_text(encoding="utf-8"))
    for key in ("modTable", "modDirectory", "ownerModuleUUID", "luaRoot"):
        if not isinstance(data.get(key), str) or not data[key]:
            raise ConfigError(f"{path}: '{key}' must be a non-empty string")
    files = data.get("files")
    if not isinstance(files, list) or not files or not all(isinstance(f, str) for f in files):
        raise ConfigError(f"{path}: 'files' must be a non-empty list of globs")
    test_filter = data.get("testFilter", {})
    if not isinstance(test_filter, dict):
        raise ConfigError(f"{path}: 'testFilter' must be an object")
    ignore_calls = data.get("ignoreCalls", [])
    if not isinstance(ignore_calls, list) or not all(isinstance(c, str) for c in ignore_calls):
        raise ConfigError(f"{path}: 'ignoreCalls' must be a list of strings")
    return Config(path.parent, data["modTable"], data["modDirectory"], data["ownerModuleUUID"],
                  data["luaRoot"], files, test_filter, ignore_calls)


def fnv1a32(data: bytes) -> str:
    """FNV-1a 32 of the raw file bytes after CRLF -> LF (lone CR and any BOM kept)."""
    h = 2166136261
    for b in data.replace(b"\r\n", b"\n"):
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return f"{h:08x}"


def build_plan(config: Config, run_id: str) -> tuple[dict, dict[str, str]]:
    """Return the plan and the patch chunks keyed by patchPath."""
    lua_root = (config.dir / config.luaRoot).resolve()
    paths = sorted({p.relative_to(lua_root).as_posix() for g in config.files for p in lua_root.glob(g) if p.is_file()})
    if not paths:
        raise ConfigError(f"no files match {config.files} under {lua_root}")
    files, mutants, chunks = [], [], {}
    for index, rel in enumerate(paths, start=1):
        source = (lua_root / rel).read_bytes()
        try:
            result = instrument(source, first_id=len(mutants) + 1)
        except SourceError as e:
            raise SourceError(f"{rel}: {e}") from None
        patch_path = f"DribbleSpecMutation/{run_id}/{index}.lua"
        chunks[patch_path] = result.chunk
        files.append({"index": index, "path": rel, "sourceHash": fnv1a32(source),
                      "patchPath": patch_path, "targets": result.targets})
        for m in result.mutants:
            record = {"file": index, **asdict(m)}
            if record["ignoredReason"] is None:
                del record["ignoredReason"]
            mutants.append(record)
    plan = {"schemaVersion": 1, "runId": run_id, "ownerModuleUUID": config.ownerModuleUUID,
            "modTable": config.modTable, "modDirectory": config.modDirectory,
            "testFilter": config.testFilter, "files": files, "mutants": mutants}
    return plan, chunks


def format_mutant(plan: dict, m: dict) -> str:
    line = f"{plan['files'][m['file'] - 1]['path']}:{m['line']} {m['operator']} {m['original']} -> {m['replacement']}"
    return line + (f"  [Ignored: {m['ignoredReason']}]" if "ignoredReason" in m else "")


def ignored_per_file(plan: dict) -> list[str]:
    """One `path: n of m ignored` line per file that has mutants."""
    lines = []
    for f in plan["files"]:
        own = [m for m in plan["mutants"] if m["file"] == f["index"]]
        if own:
            lines.append(f"{f['path']}: {sum('ignoredReason' in m for m in own)} of {len(own)} ignored")
    return lines


def next_run_id(root: Path) -> str:
    """A `YYYYMMDD-HHMMSS` run id, suffixed `-2`, `-3`, ... while that run directory exists under `root`."""
    base = run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    suffix = 1
    while (root / "DribbleSpecMutation" / run_id).exists():
        suffix += 1
        run_id = f"{base}-{suffix}"
    return run_id


def cmd_list(args) -> int:
    config = load_config(Path(args.config))
    out = Path(args.out) if args.out else config.dir / ".dribblespec-mutation"
    run_id = next_run_id(out)
    plan, chunks = build_plan(config, run_id)
    (out / "DribbleSpecMutation" / run_id).mkdir(parents=True)
    for patch_path, chunk in chunks.items():
        (out / patch_path).write_text(chunk, encoding="utf-8", newline="")
    plan_file = out / "DribbleSpecMutation" / run_id / "plan.json"
    plan_file.write_text(json.dumps(plan, indent=2), encoding="utf-8")
    for m in plan["mutants"]:
        print(format_mutant(plan, m))
    for line in ignored_per_file(plan):
        print(line)
    ignored = sum("ignoredReason" in m for m in plan["mutants"])
    print(f"{len(plan['mutants'])} mutants ({ignored} ignored) in {len(plan['files'])} files; plan: {plan_file}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dribblespec-mutate", description="Mutation testing for DribbleSpec mods.")
    sub = parser.add_subparsers(dest="command", required=True)
    p_list = sub.add_parser("list", help="list mutants and write the plan and patch chunks")
    p_list.add_argument("--config", required=True, help="path to the mutation config JSON")
    p_list.add_argument("--out", help="work directory (default: .dribblespec-mutation/ next to the config)")
    p_list.set_defaults(func=cmd_list)
    from .run import cmd_run

    p_run = sub.add_parser("run", help="run the mutants in the game and print the summary")
    p_run.add_argument("--config", required=True, help="path to the mutation config JSON")
    p_run.set_defaults(func=cmd_run)
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except (ConfigError, SourceError, OSError, json.JSONDecodeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
