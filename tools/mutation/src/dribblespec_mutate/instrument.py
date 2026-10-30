"""Parse a Lua file, find mutation sites, and build its line-preserving patch chunk."""

from dataclasses import dataclass

import tree_sitter_lua
from tree_sitter import Language, Node, Parser

PREFIX = "local __M = Mods.Dribbles.Mutation.Runtime; "
STEP = "__M.S();"

STATIC = "static"
CAPTURES = "captures file-local state"

# Each relational operator yields two mutants, in this order.
RELATIONAL = {
    "<": ("<=", ">="),
    "<=": ("<", ">"),
    ">": (">=", "<="),
    ">=": (">", "<"),
}

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


def _file_locals(root: Node) -> set[str]:
    names = set()
    for stmt in root.children:
        if _is_local_function(stmt):
            names.add(stmt.child_by_field_name("name").text.decode())
        elif stmt.type == "variable_declaration":
            for node in _walk(stmt):
                if node.type == "identifier" and node.parent.type == "variable_list":
                    names.add(node.text.decode())
    return names


def _references(body: Node, names: set[str]) -> bool:
    for node in _walk(body):
        if node.type != "identifier" or node.text.decode() not in names:
            continue
        parent = node.parent
        if parent.type in ("dot_index_expression", "method_index_expression") and parent.child_by_field_name("table") != node:
            continue
        if parent.type == "field" and parent.child_by_field_name("name") == node:
            continue
        return True
    return False


def _relational_sites(node: Node):
    for n in _walk(node):
        if n.type == "binary_expression" and n.child_by_field_name("operator").type in RELATIONAL:
            yield n


def instrument(source: bytes, first_id: int = 1) -> Instrumented:
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

    file_locals = _file_locals(root)
    reasons: dict[int, str | None] = {}  # top-level statement start byte -> ignored reason (None = target)
    targets = []
    for stmt in root.children:
        if stmt.type != "function_declaration":
            reasons[stmt.start_byte] = STATIC
            continue
        name = stmt.child_by_field_name("name")
        body = stmt.child_by_field_name("body")
        if _is_local_function(stmt) or _root_name(name).text.decode() in file_locals or (
            body is not None and _references(body, file_locals)
        ):
            reasons[stmt.start_byte] = CAPTURES
        else:
            reasons[stmt.start_byte] = None
            # Dotted form: `A:B` is stored as `A.B`, which is all the agent needs to read and reassign it.
            targets.append(name.text.decode().replace(":", "."))

    mutants: list[Mutant] = []
    site_ids: dict[tuple[int, int], int] = {}
    next_id = first_id
    for stmt in root.children:
        for site in _relational_sites(stmt):
            op = site.child_by_field_name("operator")
            row, col = op.start_point
            site_ids[(site.start_byte, site.end_byte)] = next_id
            for replacement in RELATIONAL[op.type]:
                mutants.append(Mutant(next_id, "RelationalBoundary", op.type, replacement, row + 1, col + 1, reasons[stmt.start_byte]))
                next_id += 1

    def render(node: Node) -> str:
        if node.child_count == 0:
            return node.text.decode()
        site_id = site_ids.get((node.start_byte, node.end_byte))
        if site_id is not None and node.type == "binary_expression":
            left = render(node.child_by_field_name("left"))
            right = render(node.child_by_field_name("right"))
            op = node.child_by_field_name("operator").type
            # Gaps around the operator may hold newlines; keep them so line numbers stay put.
            gap = source[node.child_by_field_name("left").end_byte : node.child_by_field_name("right").start_byte].decode()
            gap = "".join(c for c in gap if c in "\r\n")
            return f'__M.Cmp({site_id}, "{op}", ({left}), {gap}({right}))'
        out = []
        pos = node.start_byte
        for child in node.children:
            out.append(source[pos : child.start_byte].decode())
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
        if stmt.type == "comment" or reasons[stmt.start_byte] is None:
            out.append(render(stmt) if stmt.type != "comment" else text)
        else:
            out.append("".join(c if c in "\r\n" else " " for c in text))
        pos = stmt.end_byte
    out.append(source[pos:].decode())
    return Instrumented("".join(out), targets, mutants)
