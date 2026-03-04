# DribbleSpec Templates

## Minimal suite template

```lua
local D = RegisterTestGlobals()

D.describe("Suite name", { tags = { "unit" } }, function()
    D.beforeEach(function(ctx)
        -- setup
    end)

    D.test("does something", function(ctx)
        D.expect(true).toBeTruthy()
    end)
end)
```

## Runtime context template

```lua
local D = RegisterTestGlobals()

D.describe("Runtime checks", { tags = { "runtime", "server" } }, function()
    D.test("server-only behavior", function(ctx)
        ctx.requireServer()
        D.expect(Ext.IsServer()).toBe(true)
    end)
end)
```

## Entity matcher template

```lua
local D = RegisterTestGlobals()

D.describe("Entity checks", { tags = { "entity", "server" } }, function()
    D.test("entity has component", function(ctx)
        ctx.requireServer()
        local guid = "3ed74f06-3c60-42dc-83f6-f034cb47c679"
        local entity = Ext.Entity.Get(guid)
        if entity == nil then
            return
        end

        ctx.expect(guid).toBeGuid()
        ctx.expect(entity).toBeEntity()
        ctx.expect(entity).toHaveComponent("DisplayName")
    end)
end)
```

## Fixture template

```lua
local D = RegisterTestGlobals()

D.describe("Fixture flow", { tags = { "runtime", "entity" } }, function()
    D.test("spawn and restore", function(ctx)
        local snapshot = ctx.fixture.state.snapshot({ player = true })
        local handle = ctx.fixture.entity("test_dummy")
        ctx.expect(handle).toBeTruthy()
        snapshot:restore()
    end)
end)
```

## DribbleSpec include template

```lua
Ext.Require("Shared/MyMod/Tests/Smoke.test.lua")
Ext.Require("Shared/MyMod/Tests/Entity.test.lua")
```
