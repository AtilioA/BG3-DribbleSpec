import re
from pathlib import Path

import pytest

from dribblespec_mutate import build_plan, fnv1a32, load_config
from dribblespec_mutate.instrument import instrument

FIXTURE_DIR = Path(__file__).parents[3] / "DribbleSpec/Mods/DribbleSpec/ScriptExtender/Lua/Shared/DribbleSpec/Tests/Mutation"


def test_recovery_config_plans_a_polluting_mutant_and_two_victims():
    plan, _ = build_plan(load_config(Path(__file__).parents[1] / "recovery.config.json"), "r")
    live = [(m["file"], m["original"], m["replacement"]) for m in plan["mutants"] if "ignoredReason" not in m]
    assert live == [(1, "false", "true"), (2, "*", "/"), (2, "+", "-")]


@pytest.mark.parametrize("name, hash_name, first_id", [("Fixture", "FIXTURE_HASH", 1),
                                                       ("LoopFixture", "LOOP_FIXTURE_HASH", 3)])
def test_committed_fixture_chunk_and_pinned_hash_match_fixture_source(name, hash_name, first_id):
    source = (FIXTURE_DIR / f"{name}.lua").read_bytes()
    pinned = re.search(hash_name + r' = "([0-9a-f]{8})"', (FIXTURE_DIR / "Agent.test.lua").read_text(encoding="utf-8"))

    assert instrument(source, first_id=first_id).chunk == (FIXTURE_DIR / f"{name}.patch.txt").read_bytes().decode("utf-8")
    assert fnv1a32(source) == pinned.group(1)
