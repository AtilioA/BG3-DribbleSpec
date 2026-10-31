import itertools

import pytest

from dribblespec_mutate.instrument import _PARSER, ALIASES, CAPTURES, STATIC, SourceError, _walk, instrument


def mutate_text(source: str, mutant) -> str:
    """Apply one mutant to the original text (the oracle for the differential tests)."""
    lines = source.split("\n")
    line = lines[mutant.line - 1]
    col = mutant.column - 1
    assert line[col : col + len(mutant.original)] == mutant.original
    start = sum(len(l) + 1 for l in lines[: mutant.line - 1]) + col
    end = start + len(mutant.original)
    if mutant.operator == "LogicalOperator":
        # `or` binds looser than `and`, so parenthesise to keep the tree of the original expression.
        node = next(n for n in _walk(_PARSER.parse(source.encode()).root_node)
                    if n.type == "binary_expression" and n.child_by_field_name("operator").start_byte == start)
        left, right = node.child_by_field_name("left"), node.child_by_field_name("right")
        b = source.encode()
        text = f"(({b[left.start_byte:left.end_byte].decode()}) {mutant.replacement} ({b[right.start_byte:right.end_byte].decode()}))"
        return (b[: node.start_byte] + text.encode() + b[node.end_byte :]).decode()
    if mutant.operator == "RemoveCall":
        end = _balanced(source, source.index("(", end))
    elif mutant.operator in ("ConditionTrue", "ConditionFalse"):
        end = _balanced(source, start, stop=" then")
    gap = "".join(c for c in source[start:end] if c == "\n")
    return source[:start] + mutant.replacement + gap + source[end:]


def _balanced(source: str, pos: int, stop: str | None = None) -> int:
    """End of the parenthesised group at pos, or of the text before `stop` at bracket depth 0 (no strings)."""
    depth = 0
    while True:
        if stop and depth == 0 and source.startswith(stop, pos):
            return pos
        c = source[pos]
        depth += (c in "([{") - (c in ")]}")
        pos += 1
        if not stop and depth == 0:
            return pos


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
    assert _reasons(src) == {2: {CAPTURES}, 4: {CAPTURES}}


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
    assert all(m.ignoredReason is None for m in result.mutants) and len(result.mutants) == 13
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
        "local __M = Mods.Dribbles.Mutation.Runtime; function F(t) __M.S(); while (not __M.On(1)) do __M.S(); end"
        " for i=1,2 do __M.S(); end for k in t do __M.S(); end repeat __M.S(); until (not __M.On(2)) end\n"
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
    # Flipping the loop literals in InRange (`while false`, `until true`) never terminates; OPS_FIXTURE covers booleans.
    patched = [m for m in result.mutants if m.ignoredReason is None and m.operator != "BooleanLiteral"]
    assert len(patched) == 16  # Vec.Less, Vec.AtMost, Odd.Gt, Odd.Le, and InRange: three relational, one logical, one arithmetic
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


OPS_FIXTURE = """\
Calls = 0
function bump(v) Calls = Calls + 1 return v end
function multi() return 1, 2 end
MT = {
    __eq = function(a, b) return a.n == b.n end,
    __add = function(a, b) return a.n + b.n + 100 end,
    __sub = function(a, b) return a.n - b.n - 100 end,
    __mul = function(a, b) return a.n * b.n * 10 end,
    __div = function(a, b) return a.n / b.n / 10 end,
}
function W(n) return setmetatable({ n = n }, MT) end
function Eq(a, b) return W(a) == W(b), a ~= b, multi() == 1 end
function Ar(a, b) return W(a) + W(b), W(a) - W(b), W(a) * W(b), W(a) / W(b), a + multi(), a - b end
function Lg(a, b)
    return bump(a) and bump(b), bump(a) or bump(b), a and b and a
        and b, (a or (b or (a and b))), a and multi(), Calls
end
function Nt(a) return not a, not not a, true, false end
function Cd(a, b)
    local r = 0
    if bump(a) then r = 1 elseif not b then r = 2 elseif a and
        b then r = 3 else r = 4 end
    return r, Calls
end
function Log(a) Calls = Calls + 100 end
function Rm(a) bump(a) Log(a) bump(a)
    if a then bump(a) end return Calls end
"""

OPS_CALLS = {
    "Eq": list(itertools.product([1, 2], [1, 2])),
    "Ar": list(itertools.product([1, 3], [1, 2])),
    "Lg": list(itertools.product([False, None, 0, 1], [False, 1])),
    "Nt": [(False,), (None,), (0,)],
    "Cd": list(itertools.product([False, 1], [False, 1])),
    "Rm": [(False,), (1,)],
}


def _outcome(lua, name, *args):
    try:
        return _call(lua, name, *args)
    except Exception:
        return "error"


def _differential(src: str, ignore_calls=()):
    from conftest import Lua

    result = instrument(src.encode(), ignore_calls=list(ignore_calls))
    patched = [m for m in result.mutants if m.ignoredReason is None]
    for m in [None] + patched:
        oracle, subject = Lua(), Lua()
        install(oracle, mutate_text(src, m) if m else src)
        install(subject, src, result.chunk)
        subject.runtime.a = m.id if m else 0
        for name, inputs in OPS_CALLS.items():
            for args in inputs:
                assert _outcome(subject, name, *args) == _outcome(oracle, name, *args), (m, name, args)
    return result


def test_every_operator_matches_its_textual_mutation():
    result = _differential(OPS_FIXTURE)
    ops = {m.operator for m in result.mutants}
    assert ops == {"EqualityOperator", "ArithmeticOperator", "LogicalOperator", "RemoveNot", "BooleanLiteral",
                   "ConditionTrue", "ConditionFalse", "RemoveCall"}
    assert instrument(OPS_FIXTURE.encode()).chunk.count("\n") == OPS_FIXTURE.count("\n")


def test_ignored_calls_produce_no_mutant_and_use_no_id():
    result = _differential(OPS_FIXTURE, ignore_calls=["Log"])
    calls = [m.original for m in result.mutants if m.operator == "RemoveCall"]
    assert calls == ["bump", "bump", "bump"]
    ids = [m.id for m in result.mutants]
    assert ids == list(range(1, len(ids) + 1))


def test_mutant_texts_per_operator():
    src = "function F(a, b)\n  if a == b then f(a) end\n  return a ~= b, a + b, a - b, a * b, a / b, a and b, a or b, not a, true, false\nend\n"
    got = [(m.operator, m.original, m.replacement) for m in instrument(src.encode()).mutants]
    assert got == [
        ("ConditionTrue", "a == b", "true"), ("ConditionFalse", "a == b", "false"),
        ("EqualityOperator", "==", "~="), ("RemoveCall", "f", ""),
        ("EqualityOperator", "~=", "=="), ("ArithmeticOperator", "+", "-"), ("ArithmeticOperator", "-", "+"),
        ("ArithmeticOperator", "*", "/"), ("ArithmeticOperator", "/", "*"),
        ("LogicalOperator", "and", "or"), ("LogicalOperator", "or", "and"),
        ("RemoveNot", "not", ""), ("BooleanLiteral", "true", "false"), ("BooleanLiteral", "false", "true"),
    ]


def test_condition_original_is_its_first_line_up_to_60_chars():
    src = "function F(a)\n  if a == 1 or\n     a == 2 then return 1 end\n  if " + "a.b" * 30 + " then end\nend\n"
    conds = [m.original for m in instrument(src.encode()).mutants if m.operator == "ConditionTrue"]
    assert conds == ["a == 1 or", ("a.b" * 30)[:60]]


def test_chunk_level_calls_are_not_mutated():
    assert instrument(b"RequireFiles('x')\nfunction F() g() end\n").mutants[0].original == "g"
    assert len(instrument(b"RequireFiles('x')\n").mutants) == 0


@pytest.mark.parametrize("nest", [lambda n: " and ".join(["a"] * n), lambda n: "(a and " * (n - 1) + "a" + ")" * (n - 1)])
def test_logical_chain_chunk_grows_linearly(nest):
    size = lambda n: len(instrument(f"function F(a) return {nest(n)} end\n".encode()).chunk)
    assert size(20) - size(10) < 2.5 * (size(10) - size(5))


def test_logical_sites_with_varargs_or_debug_are_ignored_and_left_as_written(lua):
    src = "function V(...) return ... and 1, ... == 1 end\nfunction D(a, b) local d = debug return a and b end\n"
    result = instrument(src.encode())
    reasons = {(m.line, m.operator): m.ignoredReason for m in result.mutants}
    assert reasons == {(1, "LogicalOperator"): "varargs", (1, "EqualityOperator"): None,
                       (2, "LogicalOperator"): "references debug"}
    assert "... and 1" in result.chunk and "a and b" in result.chunk
    lua.compile(result.chunk)


def test_source_using_the_reserved_prefix_fails_hard():
    with pytest.raises(SourceError, match="__M"):
        instrument(b"function F() local __Ml = 1 return __Ml end\n")


def test_sites_in_kept_statements_are_static_and_rendered_as_written():
    src = "local DEBUG = false\nfunction A.f(x) return DEBUG end\n"
    result = instrument(src.encode())
    assert [(m.line, m.operator, m.ignoredReason) for m in result.mutants] == [(1, "BooleanLiteral", STATIC)]
    assert result.chunk.splitlines()[0].endswith("local DEBUG = false")


def test_debug_as_a_field_name_is_not_a_reference():
    src = "function F(c) return c.debug and 1, { debug = 1 } end\n"
    assert {m.ignoredReason for m in instrument(src.encode()).mutants} == {None}


def test_literal_condition_has_only_its_boolean_literal_mutant():
    src = "function F() if true then return 1 elseif false then return 2 end if (true) then return 3 end end\n"
    assert [(m.operator, m.original) for m in instrument(src.encode()).mutants] == [
        ("BooleanLiteral", "true"), ("BooleanLiteral", "false"), ("BooleanLiteral", "true")]
