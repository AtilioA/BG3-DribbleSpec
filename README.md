# DribbleSpec

DribbleSpec is a reusable Baldur's Gate 3 Script Extender test framework for Lua mods.

It gives consumer mods a small Jest-inspired test DSL (`describe`, `test`, hooks), `expect` matchers, doubles, runtime helpers, fixture helpers, and BG3 entity-aware assertions.

## Consumer guide

The detailed consumer documentation lives at [`CONSUMER_GUIDE.md`](DribbleSpec\Mods\DribbleSpec\ScriptExtender\Lua\Shared\DribbleSpec\Docs\CONSUMER_GUIDE.md), or at the [BG3 CMTY Wiki](https://wiki.bg3.community/en/Tutorials/dribblespec).

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
Ext.Require("Shared/MyMod/Tests/Smoke.test.lua")
Ext.Require("Shared/MyMod/Tests/Runtime.test.lua")
```

5. Make sure that init file is required before you run tests, then use the console:

- `!dribbles`
- `!d --tag mymod`
- `!d --tag unit`
- `!mytests`
