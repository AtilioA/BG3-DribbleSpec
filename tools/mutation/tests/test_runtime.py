import pytest
from lupa.lua53 import LuaError


def test_cmp_applies_original_operator_with_no_mutant(lua):
    r = lua.runtime
    assert r.Cmp(1, ">=", 2, 2) is True
    assert r.Cmp(1, "<", 2, 2) is False


def test_cmp_applies_each_replacement_when_its_id_is_active(lua):
    r = lua.runtime
    r.a = 1
    assert r.Cmp(1, ">=", 2, 2) is False  # >
    r.a = 2
    assert r.Cmp(1, ">=", 1, 2) is True  # <
    r.a = 3
    assert r.Cmp(1, ">=", 2, 2) is True  # other site's mutant: original


def test_cmp_records_both_ids_only_while_coverage_is_on(lua):
    r = lua.runtime
    r.Cmp(5, "<", 1, 2)
    lua.rt.execute("Mods.Dribbles.Mutation.Runtime.hits = {}")
    r.Cmp(5, "<", 1, 2)
    assert dict(r.hits) == {5: True, 6: True}


def test_step_never_raises_with_no_active_mutant(lua):
    r = lua.runtime
    r.stepLimit = 2
    for _ in range(5):
        r.S()
    assert r.steps == 5 and r.limitHit is None


def test_step_limit_raises_and_stays_set_while_mutant_active(lua):
    lua.rt.execute("""
        local R = Mods.Dribbles.Mutation.Runtime
        R.a = 1; R.stepLimit = 2
        R.S(); R.S()
        swallowed = pcall(R.S)
        ok, err = pcall(R.S)
    """)
    g = lua.rt.globals()
    assert g.swallowed is False and g.ok is False
    assert "DribbleSpecMutation: limit" in g.err
    assert lua.runtime.limitHit == "steps"


def test_deadline_checked_against_injected_clock_every_1000_steps(lua):
    lua.rt.execute("""
        local R = Mods.Dribbles.Mutation.Runtime
        now = 0
        R.clock = function() return now end
        R.a = 1; R.deadlineMs = 10
        for _ = 1, 1000 do R.S() end
        now = 11
        for _ = 1, 999 do R.S() end
    """)
    assert lua.runtime.limitHit is None  # past the deadline, but no check since step 1,000
    lua.rt.execute("pcall(Mods.Dribbles.Mutation.Runtime.S)")
    assert lua.runtime.limitHit == "time"
    with pytest.raises(LuaError, match="limit"):
        lua.runtime.S()
