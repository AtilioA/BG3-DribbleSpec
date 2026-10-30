from pathlib import Path

import lupa.lua53 as lupa
import pytest

RUNTIME = (Path(__file__).parents[3] / "DribbleSpec/Mods/DribbleSpec/ScriptExtender/Lua/Shared/DribbleSpec/Mutation/Runtime.lua")


class Lua:
    """A sandboxed Lua 5.3 state with the mutation Runtime installed at Mods.Dribbles.Mutation.Runtime."""

    def __init__(self):
        self.rt = lupa.LuaRuntime(register_eval=False, register_builtins=False)
        g = self.rt.globals()
        g.io = g.os = g.package = g.require = g.dofile = g.loadfile = None
        self.runtime = self.run(RUNTIME.read_text(encoding="utf-8"), "@Runtime.lua")
        self.rt.execute("Mods = { Dribbles = { Mutation = {} } }")
        g.Mods.Dribbles.Mutation.Runtime = self.runtime

    def compile(self, text: str, name: str = "=chunk"):
        result = self.rt.globals().load(text, name, "t")
        if isinstance(result, tuple):  # (nil, message)
            raise SyntaxError(result[1])
        return result

    def run(self, text: str, name: str = "=chunk"):
        return self.compile(text, name)()

    def eval(self, expr: str):
        return self.rt.eval(expr)


@pytest.fixture
def lua():
    return Lua()
