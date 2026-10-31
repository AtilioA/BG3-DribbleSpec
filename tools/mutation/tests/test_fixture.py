import re
from pathlib import Path

from dribblespec_mutate import fnv1a32
from dribblespec_mutate.instrument import instrument

FIXTURE_DIR = Path(__file__).parents[3] / "DribbleSpec/Mods/DribbleSpec/ScriptExtender/Lua/Shared/DribbleSpec/Tests/Mutation"


def test_committed_fixture_chunk_and_pinned_hash_match_fixture_source():
    source = (FIXTURE_DIR / "Fixture.lua").read_bytes()
    pinned = re.search(r'FIXTURE_HASH = "([0-9a-f]{8})"', (FIXTURE_DIR / "Agent.test.lua").read_text(encoding="utf-8"))

    assert instrument(source, first_id=1).chunk == (FIXTURE_DIR / "Fixture.patch.txt").read_bytes().decode("utf-8")
    assert fnv1a32(source) == pinned.group(1)
