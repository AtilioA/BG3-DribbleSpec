import itertools

import pytest

from dribblespec_mutate.instrument import ALIASES, CAPTURES, STATIC, SourceError, instrument


def mutate_text(source: str, mutant) -> str:
    """Apply one mutant to the original text (the oracle for the differential tests)."""
    lines = source.split("\n")
    line = lines[mutant.line - 1]
    col = mutant.column - 1
    assert line[col : col + len(mutant.original)] == mutant.original
    lines[mutant.line - 1] = line[:col] + mutant.replacement + line[col + len(mutant.original) :]
    return "\n".join(lines)


FIXTURE = """\
Vec = {}
VecMT = {
    __lt = function(a, b) return a.n < b.n end,
    __le = function(a, b) return a.n <= b.n end,
}
function Vec.new(n) return setmetatable({ n = n }, VecMT) end
function Vec.Less(a, b) return Vec.new(a) < Vec.new(b) end
function Vec.AtMost(a, b) return Vec.new(a)
    >= Vec.new(b) end

-- __le is not the negation of __lt, so a helper that rewrites `a > b` as `not (a <= b)` is caught.
Odd = {}
OddMT = {
    __lt = function(a, b) return a.n < b.n end,
    __le = function(a, b) return true end,
}
function Odd.new(n) return setmetatable({ n = n }, OddMT) end
function Odd.Gt(a, b) return Odd.new(a) > Odd.new(b) end
function Odd.Le(a, b) return Odd.new(a) <= Odd.new(b) end

function pair(a, b) return a, b end
function InRange(x, lo, hi)
    local count = 0
    for i = 1, 3 do count = count + 1 end
    while false do end
    repeat until true
    return pair(x, 0) >= pair(lo, 99) and x <= hi, x > lo, count
end
"""

INPUTS = list(itertools.product([0, 1, 2, 3, float("nan")], [1, 2], [2, 3]))


def _call(lua, name, *args):
    """Call a Lua function and return all its results, so multi-return differences count."""
    packed = lua.eval(f"function(...) local t = table.pack({name}(...)) return t.n, t end")(*args)
    n, t = packed
    return tuple(t[i] for i in range(1, n + 1))


FUNCS = ["Vec.Less", "Vec.AtMost", "Odd.Gt", "Odd.Le", "InRange"]


def install(lua, source: str, chunk: str | None = None):
    lua.run(source)
    if chunk is not None:
        lua.run(chunk)


def test_chunk_keeps_line_count_and_compiles(lua):
    result = instrument(FIXTURE.encode())
    assert result.chunk.count("\n") == FIXTURE.count("\n")
    lua.compile(result.chunk)


def test_chunk_keeps_crlf_line_endings():
    src = "A = {}\r\nfunction A.f(x)\r\n  return x\r\n    < 1\r\nend\r\n"
    assert instrument(src.encode()).chunk == (
        "local __M = Mods.Dribbles.Mutation.Runtime;       \r\n"
        "function A.f(x) __M.S();\r\n"
        '  return __M.Cmp(1, "<", (x), \r\n'
        "(1))\r\n"
        "end\r\n"
    )


def _reasons(src: str) -> dict[int, set]:
    by_line = {}
    for m in instrument(src.encode()).mutants:
        by_line.setdefault(m.line, set()).add(m.ignoredReason)
    return by_line


def test_targets_and_ignored_reasons():
    src = """\
local limit = 3
local function helper(x) return x < 1 end
Top = 1 < 2
function A.Uses(x) return x < limit end
function A:Method(x) return x > 0 and A.limit < 2 end
function G(x) return x >= 0, { limit = 1 } end
function limit.Field(x) return x <= 0 end
local sealed = -2
function A.Sealed(x) return x < sealed end
"""
    result = instrument(src.encode())
    assert result.targets == ["A.Uses", "A.Method", "G", "A.Sealed"]
    # helper is called by no target, so its patched copy is never reached.
    assert _reasons(src) == {2: {CAPTURES}, 3: {STATIC}, 4: {None}, 5: {None}, 6: {None}, 7: {CAPTURES}, 9: {None}}


def test_reassigned_literal_makes_users_ignored():
    src = "local n = 1\nfunction A.f(x) return x < n end\nfunction A.g() n = 2 end\n"
    assert _reasons(src) == {2: {CAPTURES}}
    assert instrument(src.encode()).targets == []


def test_redeclared_literal_makes_users_ignored():
    src = "local n = 1\nlocal n = 2\nfunction A.f(x) return x < n end\n"
    assert _reasons(src) == {3: {CAPTURES}}


def test_table_constructor_is_not_a_constant():
    src = "local t = {}\nfunction A.f(x) return x < t.n end\n"
    assert _reasons(src) == {2: {CAPTURES}}
    assert instrument(src.encode()).chunk.splitlines()[0].strip() == "local __M = Mods.Dribbles.Mutation.Runtime;"


def test_value_count_mismatch_is_not_kept():
    assert _reasons("local a, b = 1\nfunction A.f(x) return x < a end\n") == {2: {CAPTURES}}
    assert _reasons("local a, b = 1, 2\nlocal z\nfunction A.f(x) return x < b, z end\n") == {3: {None}}


def test_alias_of_target_is_ignored_and_other_aliases_kept():
    src = """\
local V = Validator
local F = Ext.Floor
function Validator.X(x) return x < 1 end
function A.f(x) return V.X(x) < 1 end
function A.g(x) return F(x) < 1 end
"""
    result = instrument(src.encode())
    assert _reasons(src) == {3: {None}, 4: {ALIASES}, 5: {None}}
    assert result.targets == ["Validator.X", "A.g"]
    assert result.chunk.splitlines()[1] == "local F = Ext.Floor"


def test_target_calling_unpatchable_local_function_is_ignored():
    src = "local t = {}\nlocal function h(x) return x < t.n end\nfunction A.f(x) return h(x) > 0 end\n"
    assert _reasons(src) == {2: {CAPTURES}, 3: {CAPTURES}}


def test_chain_of_local_functions_is_patchable():
    src = """\
local k = 1
local function a(x) return x < k end
local function b(x) if x > 9 then return b(x - 1) end return a(x) end
function A.f(x) return b(x) end
"""
    result = instrument(src.encode())
    assert _reasons(src) == {2: {None}, 3: {None}}
    assert result.targets == ["A.f"]


def test_code_outside_function_bodies_is_static():
    src = "SettingValidators = {\n  int = function(x) return x < 1 end,\n}\n"
    assert _reasons(src) == {2: {STATIC}}


def _same_behaviour(src: str, calls: list[str]):
    """Original module vs original + chunk with no mutant active, over a sequence of calls."""
    from conftest import Lua

    oracle, subject = Lua(), Lua()
    install(oracle, src)
    install(subject, src, instrument(src.encode()).chunk)
    for expr in calls:
        assert subject.eval(expr) == oracle.eval(expr), expr


def test_reassigned_local_function_makes_users_ignored():
    src = """\
local t = {}
local function h(x) return x < 1 end
function A_f(x) return h(x) end
function A_swap() t.n = 1; h = function() return true end end
"""
    _same_behaviour(src, ["A_f(5)", "A_swap()", "A_f(5)"])
    assert _reasons(src) == {2: {CAPTURES}}


def test_function_statement_on_a_local_is_an_assignment():
    src = "local h\nfunction h(x) return x < 1 end\nfunction A_f(x) return h(x) end\n"
    _same_behaviour(src, ["A_f(5)", "A_f(0)"])


def test_alias_of_a_path_the_file_writes_is_not_kept():
    src = """\
Helpers = { Clamp = function() return 1 end }
local C = Helpers.Clamp
Helpers.Clamp = function() return 2 end
function A_f(x) return C(x) < 2 end
"""
    _same_behaviour(src, ["A_f(0)"])
    assert _reasons(src) == {4: {CAPTURES}}


def test_local_function_referenced_from_blanked_code_is_ignored():
    src = "local function h(x) return x < 1 end\nfunction A_f(x) return h(x) end\nB = { g = function(x) return h(x) end }\n"
    _same_behaviour(src, ["A_f(0)", "A_f(5)"])
    assert _reasons(src) == {1: {CAPTURES}}
    assert instrument(src.encode()).targets == ["A_f"]


def test_local_function_with_an_ignored_caller_is_still_rendered():
    src = "local t = {}\nlocal function h(x) return x < 1 end\nfunction A_f(x) return h(x) end\nfunction A_g(x) return h(x), #t end\n"
    _same_behaviour(src, ["A_f(0)", "A_f(5)"])
    assert _reasons(src) == {2: {CAPTURES}}


def test_alias_of_target_wins_over_captures():
    src = """\
local V = Validator
local t = {}
function Validator.X(x) return x < 1 end
function V.Y(x) return x < 1 end
local function h(x) return x < t.n, V end
function A.f(x) return h(x) end
"""
    assert _reasons(src) == {3: {None}, 4: {ALIASES}, 5: {ALIASES}}


def test_redeclared_local_function_earlier_copy_captures():
    src = "local function h(x) return x < 1 end\nlocal function h(x) return x > 1 end\nfunction A.f(x) return h(x) end\n"
    assert _reasons(src) == {1: {CAPTURES}, 2: {CAPTURES}}


LOCAL_FIXTURE = """\
local lo = 0
local function inUnit(v) return v >= lo and v <= 1 end
local function allInUnit(t)
    for _, v in ipairs(t) do if not inUnit(v) then return false end end
    return true
end
C = {}
function C.Validate(t) return #t > 2 and allInUnit(t) end
"""


def test_local_function_mutants_are_reached_through_the_target():
    from conftest import Lua

    result = instrument(LOCAL_FIXTURE.encode())
    assert result.targets == ["C.Validate"]
    assert all(m.ignoredReason is None for m in result.mutants) and len(result.mutants) == 6
    inputs = [[0, 1, 0.5], [1, 1], [-0.1, 0, 0], [0, 0, 1.1], [0, 1, 0], [1, 1, 1, 1]]
    for active in [0] + [m.id for m in result.mutants]:
        oracle, subject = Lua(), Lua()
        m = next((m for m in result.mutants if m.id == active), None)
        install(oracle, mutate_text(LOCAL_FIXTURE, m) if m else LOCAL_FIXTURE)
        install(subject, LOCAL_FIXTURE, result.chunk)
        subject.runtime.a = active
        for t in inputs:
            assert _call(subject, "C.Validate", subject.rt.table(*t)) == _call(oracle, "C.Validate", oracle.rt.table(*t)), (m, t)


def test_step_counter_at_function_entry_and_every_loop_body():
    src = "function F(t) while true do end for i=1,2 do end for k in t do end repeat until true end\n"
    assert instrument(src.encode()).chunk == (
        "local __M = Mods.Dribbles.Mutation.Runtime; function F(t) __M.S(); while true do __M.S(); end"
        " for i=1,2 do __M.S(); end for k in t do __M.S(); end repeat __M.S(); until true end\n"
    )


def test_mutant_ids_are_consecutive_in_source_order_with_one_based_columns():
    src = "function F(a, b) return a < b, a >= b end\n"
    ms = instrument(src.encode(), first_id=7).mutants
    assert [(m.id, m.original, m.replacement, m.line, m.column) for m in ms] == [
        (7, "<", "<=", 1, 27), (8, "<", ">=", 1, 27), (9, ">=", ">", 1, 34), (10, ">=", "<", 1, 34),
    ]


def test_original_behaviour_when_no_mutant_is_active(lua):
    from conftest import Lua

    expected_lua = Lua()
    install(expected_lua, FIXTURE)
    install(lua, FIXTURE, instrument(FIXTURE.encode()).chunk)
    for name in FUNCS:
        for args in INPUTS:
            assert _call(lua, name, *args) == _call(expected_lua, name, *args), (name, args)


def test_each_active_mutant_matches_the_textual_mutation():
    from conftest import Lua

    result = instrument(FIXTURE.encode())
    patched = [m for m in result.mutants if m.ignoredReason is None]
    assert len(patched) == 14  # Vec.Less, Vec.AtMost, Odd.Gt, Odd.Le, and three InRange sites
    for m in patched:
        oracle, subject = Lua(), Lua()
        install(oracle, mutate_text(FIXTURE, m))
        install(subject, FIXTURE, result.chunk)
        subject.runtime.a = m.id
        for name in FUNCS:
            for args in INPUTS:
                assert _call(subject, name, *args) == _call(oracle, name, *args), (m, name, args)


def test_parses_floor_division_bitwise_goto_and_labels(lua):
    src = """\
function F(x)
    local y = x // 2 | 1 & 3 ~ 4 << 1 >> 1
    y = ~y
    ::top::
    if y < 0 then goto done end
    y = y - 1
    goto top
    ::done::
    return y
end
"""
    result = instrument(src.encode())
    assert result.targets == ["F"]
    lua.compile(result.chunk)


def test_syntax_error_fails_hard():
    with pytest.raises(SourceError, match="syntax error"):
        instrument(b"function F()\n  return (\nend\n")


def test_non_utf8_source_fails_hard():
    with pytest.raises(SourceError, match="not valid UTF-8"):
        instrument(b"function F() return '\xe9' end\n")


def test_bom_is_dropped_so_the_prefix_comes_first(lua):
    src = b"\xef\xbb\xbfA = {}\nfunction A.f(x) return x < 1 end\n"
    chunk = instrument(src).chunk
    assert chunk.startswith("local __M = ")
    lua.compile(chunk)
