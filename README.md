# DribbleSpec

DribbleSpec is a reusable Baldur's Gate 3 Script Extender test framework for Lua mods.

It gives consumer mods a small test DSL (`describe`, `test`, hooks), `expect` matchers, doubles, runtime helpers, fixture helpers, and BG3 entity-aware assertions.

## Quickstart

1. Make sure DribbleSpec is loaded with your mod.
2. In your test files, register the public API:

```lua
D = Mods.Dribbles.RegisterTestGlobals({
    ownerModuleUUID = ModuleUUID,
    globalTags = { "mymod" },
    commandAlias = "mytests",
})
```

3. Write a minimal test:

```lua
D = Mods.Dribbles.RegisterTestGlobals()

D.describe("MyMod smoke", { tags = { "unit" } }, function()
    D.test("basic truthiness", function()
        D.expect(true).toBeTruthy()
    end)
end)
```

4. Load your test files explicitly from your mod's own test init file:

```lua
-- Shared/MyMod/Tests/_Init.lua
Ext.Require("Shared/MyMod/Tests/Smoke.test.lua")
Ext.Require("Shared/MyMod/Tests/Runtime.test.lua")
```

5. Make sure that init file is required before you run tests, then use the console:

- `dribbles`
- `d --name smoke`
- `dribbles --tag runtime --tag server`
- `mytests`

## Consumer Guide

The detailed consumer documentation lives at `DribbleSpec/Mods/DribbleSpec/ScriptExtender/Lua/Shared/DribbleSpec/Docs/CONSUMER_GUIDE.md`.

Start there for:

- registration and exported symbols
- context helpers and skipping
- doubles, fixtures, and entity matchers
- troubleshooting and extension points

## Repository Notes

- The shipped mod content lives under `DribbleSpec/`.
- Internal planning docs and local release helpers are intentionally kept out of the public tree.
- License: `AGPL-3.0-only`; see `LICENSE`.
