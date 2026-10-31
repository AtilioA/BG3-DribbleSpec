"""Parse a Lua file, find mutation sites, and build its line-preserving patch chunk."""

from collections.abc import Sequence
from dataclasses import dataclass

import tree_sitter_lua
from tree_sitter import Language, Node, Parser

PREFIX = "local __M = Mods.Dribbles.Mutation.Runtime; "
STEP = "__M.S();"

STATIC = "static"
CAPTURES = "captures file-local state"
ALIASES = "aliases a target"

VARARGS = "varargs"
REFERENCES_DEBUG = "references debug"

# Each relational operator yields two mutants, in this order.
RELATIONAL = {
    "<": ("<=", ">="),
    "<=": ("<", ">"),
    ">": (">=", "<="),
    ">=": (">", "<"),
}
EQUALITY = {"==": "~=", "~=": "=="}
ARITH = {"+": "-", "-": "+", "*": "/", "/": "*"}
LOGICAL = {"and": "or", "or": "and"}

_PARSER = Parser(Language(tree_sitter_lua.language()))


class SourceError(Exception):
    pass


@dataclass
class Mutant:
    id: int
    operator: str
    original: str
    replacement: str
    line: int
    column: int
    ignoredReason: str | None = None


@dataclass
class Instrumented:
    chunk: str
    targets: list[str]
    mutants: list[Mutant]


def _walk(node: Node):
    yield node
    for child in node.children:
        yield from _walk(child)


def _is_local_function(node: Node) -> bool:
    return node.type == "function_declaration" and node.children[0].type == "local"


def _root_name(name: Node) -> Node:
    while name.type in ("dot_index_expression", "method_index_expression"):
        name = name.child_by_field_name("table")
    return name


def _path(node: Node) -> str | None:
    """Dotted text of a global path expression (`A`, `A.B.C`), or None."""
    if node.type == "identifier":
        return node.text.decode()
    if node.type == "dot_index_expression":
        base = _path(node.child_by_field_name("table"))
        return base and f"{base}.{node.child_by_field_name('field').text.decode()}"
    return None


def _is_literal(node: Node) -> bool:
    if node.type in ("nil", "true", "false", "number", "string"):
        return True
    return node.type == "unary_expression" and node.children[0].type == "-" and node.children[1].type == "number"


def _declared(stmt: Node) -> list[tuple[str, str, str | None]]:
    """(name, kind, alias path) per name of a top-level `local`; kind is "literal", "alias", or "other"."""
    assign = next((c for c in stmt.children if c.type == "assignment_statement"), None)
    names_node = assign.children[0] if assign else next(c for c in stmt.children if c.type == "variable_list")
    names = [c.text.decode() for c in names_node.named_children if c.type == "identifier"]
    if assign is None:
        return [(n, "literal", None) for n in names]
    values = next(c for c in assign.children if c.type == "expression_list").named_children
    if len(values) != len(names):
        return [(n, "other", None) for n in names]
    out = []
    for n, v in zip(names, values):
        path = _path(v)
        out.append((n, "literal" if _is_literal(v) else "alias" if path else "other", path))
    return out


def _written(root: Node) -> set[str]:
    """Dotted paths the file writes: `x = ...`, `A.b = ...`, and `function x(...)` / `function A.b(...)`."""
    paths = set()
    for node in _walk(root):
        if node.type == "assignment_statement" and node.parent.type != "variable_declaration":
            paths.update(p for c in node.children[0].named_children if (p := _path(c)))
        elif node.type == "function_declaration" and not _is_local_function(node):
            paths.add(node.child_by_field_name("name").text.decode().replace(":", "."))
    return paths


def _worst(a: str | None, b: str | None) -> str | None:
    return ALIASES if ALIASES in (a, b) else a or b


def _references(body: Node, names) -> set[str]:
    found = set()
    for node in _walk(body):
        if node.type != "identifier" or node.text.decode() not in names:
            continue
        parent = node.parent
        if parent.type in ("dot_index_expression", "method_index_expression") and parent.child_by_field_name("table") != node:
            continue
        if parent.type == "field" and parent.child_by_field_name("name") == node:
            continue
        found.add(node.text.decode())
    return found


def _first_line(text: str) -> str:
    return text.splitlines()[0].rstrip()[:60]


def _enclosing_function(node: Node) -> Node | None:
    while node is not None and node.type not in ("function_declaration", "function_definition"):
        node = node.parent
    return node


def _sites(stmt: Node, ignore_calls: set[str]):
    """(node, kind, operator, mutants as (operator name, original, replacement, anchor node)) in pre-order."""
    for n in _walk(stmt):
        if n.type == "binary_expression":
            op = n.child_by_field_name("operator")
            if op.type in RELATIONAL:
                yield n, "cmp", [("RelationalBoundary", op.type, r, op) for r in RELATIONAL[op.type]]
            elif op.type in EQUALITY:
                yield n, "cmp", [("EqualityOperator", op.type, EQUALITY[op.type], op)]
            elif op.type in ARITH:
                yield n, "arith", [("ArithmeticOperator", op.type, ARITH[op.type], op)]
            elif op.type in LOGICAL:
                yield n, "logical", [("LogicalOperator", op.type, LOGICAL[op.type], op)]
        elif n.type == "unary_expression" and n.children[0].type == "not":
            yield n, "not", [("RemoveNot", "not", "", n.children[0])]
        elif n.type in ("true", "false") and n.child_count == 0:
            yield n, "bool", [("BooleanLiteral", n.type, "false" if n.type == "true" else "true", n)]
        elif n.type in ("if_statement", "elseif_statement"):
            c = n.child_by_field_name("condition")
            inner = c
            while inner.type == "parenthesized_expression":
                inner = inner.named_children[0]
            if inner.type in ("true", "false"):
                continue  # Its BooleanLiteral mutant already covers both forced values.
            text = _first_line(c.text.decode())
            yield c, "cond", [("ConditionTrue", text, "true", c), ("ConditionFalse", text, "false", c)]
        elif n.type == "function_call" and n.parent.type == "block":
            callee = n.child_by_field_name("name")
            if callee.text.decode() not in ignore_calls:
                yield n, "call", [("RemoveCall", callee.text.decode(), "", callee)]


def instrument(source: bytes, first_id: int = 1, ignore_calls: Sequence[str] = ()) -> Instrumented:
    """Return the patch chunk, target names, and mutants (ids from first_id) for one file."""
    try:
        source.decode("utf-8")
    except UnicodeDecodeError as e:
        raise SourceError(f"not valid UTF-8 at byte {e.start}") from None
    # A BOM would sit before the prefix and break the chunk; columns are counted after it.
    source = source.removeprefix(b"\xef\xbb\xbf")
    tree = _PARSER.parse(source)
    root = tree.root_node
    if root.has_error:
        bad = [n for n in _walk(root) if n.is_error or n.is_missing][-1]
        row, col = bad.start_point
        raise SourceError(f"syntax error at line {row + 1}, column {col + 1}")
    reserved = next((n for n in _walk(root) if n.type == "identifier" and n.text.startswith(b"__M")), None)
    if reserved is not None:
        row, col = reserved.start_point
        raise SourceError(f"identifier {reserved.text.decode()} at line {row + 1}, column {col + 1} uses the reserved prefix __M")

    funcs = [s for s in root.children if s.type == "function_declaration"]
    # Global function names: an alias of one (or of a table holding one) would capture the unpatched value.
    global_names = [f.child_by_field_name("name").text.decode().replace(":", ".") for f in funcs if not _is_local_function(f)]
    written = _written(root)
    seen: set[str] = set()
    kinds: dict[str, str | None] = {}  # file local -> reason its users get (None = safe)
    kept: set[int] = set()  # start bytes of kept non-target statements
    local_funcs: dict[str, Node] = {}  # name -> its last declaration
    reasons: dict[int, str | None] = {}  # top-level statement start byte -> ignored reason (None = rendered)
    for stmt in root.children:
        if _is_local_function(stmt):
            name = stmt.child_by_field_name("name").text.decode()
            if name in seen:
                kinds[name] = CAPTURES
                if name in local_funcs:
                    reasons[local_funcs[name].start_byte] = CAPTURES
            elif name in written:
                kinds[name] = CAPTURES
            seen.add(name)
            local_funcs[name] = stmt
        elif stmt.type == "variable_declaration":
            stmt_kinds = {}
            for name, kind, path in _declared(stmt):
                if name in seen or name in written or kind == "other":
                    stmt_kinds[name] = CAPTURES
                elif kind == "literal":
                    stmt_kinds[name] = None
                elif any(t == path or t.startswith(path + ".") for t in global_names):
                    stmt_kinds[name] = ALIASES
                elif path.split(".")[0] in seen or any(path == w or path.startswith(w + ".") for w in written):
                    # Kept statements are re-run at chunk load, so the path must hold the same value then.
                    stmt_kinds[name] = CAPTURES
                else:
                    stmt_kinds[name] = None
                seen.add(name)
            if all(k is None for k in stmt_kinds.values()):
                kept.add(stmt.start_byte)
            # A blanked statement takes all its names with it.
            for name, k in stmt_kinds.items():
                kinds[name] = k if stmt.start_byte in kept else _worst(k, CAPTURES)
    for name in local_funcs:
        kinds.setdefault(name, None)

    def refs(stmt: Node) -> set[str]:
        node = stmt.child_by_field_name("body") if _is_local_function(stmt) else stmt
        return _references(node, kinds) if node is not None else set()

    # Reason of each local function including what it calls, solved to a fixed point (handles recursion).
    lf_reason = {name: kinds[name] for name in local_funcs}
    changed = True
    while changed:
        changed = False
        for name, stmt in local_funcs.items():
            r = lf_reason[name]
            for dep in refs(stmt):
                r = _worst(r, lf_reason.get(dep, kinds[dep]))
            if r != lf_reason[name]:
                lf_reason[name], changed = r, True

    targets = []
    installed: set[int] = set()
    for stmt in funcs:
        if _is_local_function(stmt):
            continue
        name = stmt.child_by_field_name("name")
        root_name = _root_name(name).text.decode()
        reason = _worst(kinds[root_name], CAPTURES) if root_name in seen else None
        for dep in refs(stmt):
            reason = _worst(reason, lf_reason.get(dep, kinds[dep]))
        reasons[stmt.start_byte] = reason
        if reason is None:
            installed.add(stmt.start_byte)
            # Dotted form: `A:B` is stored as `A.B`, which is all the agent needs to read and reassign it.
            targets.append(name.text.decode().replace(":", "."))

    # Render every local function installed code reaches through safe local functions, so no call hits a blanked one.
    safe = {n for n, r in lf_reason.items() if r is None}
    rendered_lf, pending = set(), [s for s in funcs if s.start_byte in installed]
    while pending:
        for n in refs(pending.pop()) & safe - rendered_lf:
            rendered_lf.add(n)
            pending.append(local_funcs[n])
    # Its mutants are patchable only if every reference to it is in patched code.
    referrers = {n: [s for s in root.children if n in refs(s) and s is not local_funcs[n]] for n in local_funcs}
    patchable = set(rendered_lf)
    while True:
        patched = installed | {local_funcs[n].start_byte for n in patchable}
        keep = {n for n in patchable if all(s.start_byte in patched for s in referrers[n])}
        if keep == patchable:
            break
        patchable = keep
    rendered = installed | kept | {local_funcs[n].start_byte for n in rendered_lf}
    for name, stmt in local_funcs.items():
        reasons[stmt.start_byte] = None if name in patchable else lf_reason[name] or CAPTURES
    # Kept statements run once at chunk load, outside any target, so their sites are static too.
    for stmt in root.children:
        reasons.setdefault(stmt.start_byte, STATIC)

    mutants: list[Mutant] = []
    site_ids: dict[tuple[int, int, str], int] = {}  # (start, end, kind) -> first id; absent = rendered as written
    next_id = first_id
    ignored_calls = set(ignore_calls)
    for stmt in root.children:
        for site, kind, forms in _sites(stmt, ignored_calls):
            reason = reasons[stmt.start_byte]
            if reason is None and kind == "logical":
                # The closure form cannot hold `...`, and it adds a stack frame that `debug` callers would see.
                func = _enclosing_function(site)
                if any(n.type == "vararg_expression" for n in _walk(site)):
                    reason = VARARGS
                elif func is not None and _references(func, {"debug"}):
                    reason = REFERENCES_DEBUG
            if reason is None:
                site_ids[(site.start_byte, site.end_byte, kind)] = next_id
            for operator, original, replacement, anchor in forms:
                row, col = anchor.start_point
                mutants.append(Mutant(next_id, operator, original, replacement, row + 1, col + 1, reason))
                next_id += 1

    def newlines(start: int, end: int) -> str:
        # Gaps around dropped or moved tokens may hold newlines; keep them so line numbers stay put.
        return "".join(c for c in source[start:end].decode() if c in "\r\n")

    def render(node: Node, skip_call: bool = False) -> str:
        key = (node.start_byte, node.end_byte)
        if node.type in ("true", "false") and (site_id := site_ids.get((*key, "bool"))) is not None:
            return f"(not __M.On({site_id}))" if node.type == "true" else f"(__M.On({site_id}))"
        if node.child_count == 0:
            return node.text.decode()
        if node.type == "binary_expression":
            left_node, right_node = node.child_by_field_name("left"), node.child_by_field_name("right")
            for kind in ("cmp", "arith", "logical"):
                site_id = site_ids.get((*key, kind))
                if site_id is None:
                    continue
                left, right = render(left_node), render(right_node)
                gap = newlines(left_node.end_byte, right_node.start_byte)
                op = node.child_by_field_name("operator").type
                if kind == "logical":
                    test = ("if __Ml then return __Ml end elseif not __Ml then return __Ml end" if op == "and"
                            else "if not __Ml then return __Ml end elseif __Ml then return __Ml end")
                    return (f"(function() local __Ml = ({left}) if __M.On({site_id}) then {test} "
                            f"return {gap}({right}) end)()")
                helper = "Cmp" if kind == "cmp" else "Arith"
                return f'__M.{helper}({site_id}, "{op}", ({left}), {gap}({right}))'
        if node.type == "unary_expression" and (site_id := site_ids.get((*key, "not"))) is not None:
            operand = node.child_by_field_name("operand")
            return f"__M.Not({site_id}, {newlines(node.start_byte, operand.start_byte)}({render(operand)}))"
        if not skip_call and node.type == "function_call" and (site_id := site_ids.get((*key, "call"))) is not None:
            return f"if not __M.On({site_id}) then {render(node, skip_call=True)} end"
        out = []
        pos = node.start_byte
        for child in node.children:
            out.append(source[pos : child.start_byte].decode())
            cond_id = site_ids.get((child.start_byte, child.end_byte, "cond"))
            if cond_id is not None and child == node.child_by_field_name("condition"):
                # A forced condition is not evaluated, as in the textual `if true then`.
                out.append(f"(__M.On({cond_id}) or not __M.On({cond_id + 1}) and ({render(child)}))")
            else:
                out.append(render(child))
            pos = child.end_byte
            if child.type == "parameters" and node.type == "function_declaration":
                out.append(" " + STEP)
            elif (child.type == "do" and node.type in ("for_statement", "while_statement")) or (
                child.type == "repeat" and node.type == "repeat_statement"
            ):
                out.append(" " + STEP)
        out.append(source[pos : node.end_byte].decode())
        return "".join(out)

    out = [PREFIX]
    pos = 0
    for stmt in root.children:
        out.append(source[pos : stmt.start_byte].decode())
        text = stmt.text.decode()
        if stmt.type == "comment" or stmt.start_byte in rendered:
            out.append(render(stmt) if stmt.type != "comment" else text)
        else:
            out.append("".join(c if c in "\r\n" else " " for c in text))
        pos = stmt.end_byte
    out.append(source[pos:].decode())
    return Instrumented("".join(out), targets, mutants)
