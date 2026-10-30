import itertools

import pytest

from dribblespec_mutate.instrument import CAPTURES, STATIC, SourceError, instrument


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


def test_targets_and_ignored_reasons():
    src = """\
local limit = 3
local function helper(x) return x < 1 end
Top = 1 < 2
function A.Uses(x) return x < limit end
function A:Method(x) return x > 0 and A.limit < 2 end
function G(x) return x >= 0, { limit = 1 } end
function limit.Field(x) return x <= 0 end
local sealed <const> = 2
function A.Sealed(x) return x < sealed end
"""
    result = instrument(src.encode())
    assert result.targets == ["A.Method", "G"]
    by_line = {}
    for m in result.mutants:
        by_line.setdefault(m.line, set()).add(m.ignoredReason)
    assert by_line == {2: {CAPTURES}, 3: {STATIC}, 4: {CAPTURES}, 5: {None}, 6: {None}, 7: {CAPTURES}, 9: {CAPTURES}}


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
