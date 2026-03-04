# DribbleSpec Guide

## What DribbleSpec provides

DribbleSpec is a reusable BG3SE Lua test framework that provides:

- Jest-like test DSL (`describe`, `test`, hooks)
- Assertions (`expect`, core + entity domain matchers)
- Doubles (`mockFn`, `spyOn`, `stub` via test `ctx`)
- Runtime helpers (`requireClient`, `requireServer`, `nextTick`, `waitUntil`)
- Fixture pipeline (preplaced first, spawn fallback)
- Entity helpers (`entityRef`) and volatile-aware equality

## Quick start

1. Ensure DribbleSpec is loaded in your mod load order.
2. Call `RegisterTestGlobals()` and assign the returned table to your namespace:

```lua
local D = RegisterTestGlobals()
```

This returns a symbol table with all relevant exports.

## Exported symbols

After `RegisterTestGlobals()`, these symbols are available on the returned table:

- `RegisterTestGlobals`
- `describe`
- `test`
- `it`
- `beforeAll`
- `beforeEach`
- `afterEach`
- `afterAll`
- `expect`
- `entityRef`

`RegisterTestGlobals()` only returns a table of exports. Your mod decides where to assign it (`D`, `Dribbles`, local variable, etc.).

## Minimal test file example

```lua
local D = RegisterTestGlobals()

D.describe("MyMod smoke", { tags = { "unit" } }, function()
    D.test("basic truthiness", function()
        D.expect(true).toBeTruthy()
    end)
end)
```

## Test loading setup (`DribbleTests.lua`)

Create test files in your consumer mod and load them explicitly:

```lua
Ext.Require("Shared/MyMod/Tests/Smoke.test.lua")
Ext.Require("Shared/MyMod/Tests/Runtime.test.lua")
```

## Running tests

Use DribbleSpec console command:

- run all: `dribble`
- help: `dribble --help`
- name filter: `dribble --name "migration"`
- tag filter: `dribble --tag runtime --tag server`
- context: `dribble --context server`
- fail fast: `dribble --fail-fast`

## Unit test example

```lua
local D = RegisterTestGlobals()

D.describe("Settings model", { tags = { "unit" } }, function()
    D.test("toEqual with volatile preset", function()
        local expected = {
            stable = { enabled = true },
            RuntimeEntityId = 100,
        }
        local actual = {
            stable = { enabled = true },
            RuntimeEntityId = 999,
        }

        D.expect(actual).toEqual(expected, { volatilePreset = "entity" })
    end)
end)
```

## Runtime test example

```lua
local D = RegisterTestGlobals()

D.describe("Runtime tick behavior", { tags = { "runtime", "client" } }, function()
    D.test("nextTick waits exactly one boundary", function(ctx)
        ctx.requireClient()
        local before = 0
        ctx.nextTick()
        local after = 1
        ctx.expect(after).toBe(before + 1)
    end)
end)
```

## Entity test example (server)

`DisplayName` assertions should run in server context.

```lua
local D = RegisterTestGlobals()

D.describe("Entity checks", { tags = { "entity", "server" } }, function()
    D.test("preplaced entity has DisplayName", function(ctx)
        ctx.requireServer()

        local guid = "3ed74f06-3c60-42dc-83f6-f034cb47c679"
        local entity = Ext.Entity.Get(guid)
        if entity == nil then
            return
        end

        ctx.expect(guid).toBeGuid()
        ctx.expect(entity).toBeEntity()
        ctx.expect(entity).toHaveComponent("DisplayName")

        local ref = ctx.entityRef(guid)
        ctx.expect(ref).toBeEntity()
    end)
end)
```

## Doubles example

```lua
local D = RegisterTestGlobals()

D.describe("Doubles", { tags = { "unit" } }, function()
    D.test("spy and assertions", function(ctx)
        local target = {
            Add = function(a, b)
                return a + b
            end,
        }

        local spy = ctx.spyOn(target, "Add")
        local value = target.Add(2, 3)

        ctx.expect(value).toBe(5)
        ctx.expect(spy).toHaveBeenCalledTimes(1)
        ctx.expect(spy).toHaveBeenCalledWith(2, 3)
    end)
end)
```

## Fixture example

```lua
local D = RegisterTestGlobals()

D.describe("Fixture usage", { tags = { "runtime", "entity" } }, function()
    D.test("spawn fallback fixture and restore state", function(ctx)
        local snapshot = ctx.fixture.state.snapshot({
            player = true,
        })

        local handle = ctx.fixture.entity("test_dummy")
        ctx.expect(handle).toBeTruthy()

        snapshot:restore()
    end)
end)
```

## Extending DribbleSpec for mod-specific needs

Use runner options to plug custom fixture behavior:

```lua
local D = RegisterTestGlobals()
local run = D.Run({
    fixtureProviders = {
        {
            name = "mod-preplaced",
            Resolve = function(request)
                if request.alias == "boss" then
                    return {
                        guid = "11111111-2222-3333-4444-555555555555",
                        value = Ext.Entity.Get("11111111-2222-3333-4444-555555555555"),
                    }
                end
                return nil
            end,
        },
    },
})
```

Other extension points:

- `fixtureAliases` for alias-to-spec lookup
- `fixtureSpawner` for custom spawn behavior
- `--tag destructive` for explicitly opt-in world mutation suites

## Troubleshooting

- `RegisterTestGlobals` missing
  - Ensure DribbleSpec bootstrap loaded before consumer test scripts.
- entity component mismatch on client
  - move component assertions (especially `DisplayName`) to server context.
- no tests executed
  - verify `DribbleTests.lua` exists and includes your test init file.
