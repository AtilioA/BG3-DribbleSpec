# DribbleSpec Guide

## What DribbleSpec provides

DribbleSpec is a reusable BG3SE Lua test framework that provides:

- Jest-like test DSL (`describe`, `test`, hooks)
- Assertions (`expect`, core + entity domain matchers)
- Doubles (`mockFn`, `spyOn`, `stub` via test `ctx`)
- Runtime helpers (`requireClient`, `requireServer`, `nextTick`, `waitUntil`)
- Fixture pipeline (preplaced first, spawn fallback)
- Entity helpers (`entityRef`) and volatile-aware equality
- IDE helpers (`DribblesIdeHelpers.lua` in `Docs/`)

## Quick start

1. Ensure DribbleSpec is loaded in your mod load order.
2. Call `RegisterTestGlobals()` and assign the returned table to your namespace:

```lua
local D = RegisterTestGlobals()
```

You can configure one-time defaults for your mod:

```lua
local D = RegisterTestGlobals({
    ownerModuleUUID = ModuleUUID,
    globalTags = { "mymod" },
    commandAlias = "mytests",
})

```

This will:
1. Register a console command `mytests` that runs only your mod tests
2. Tag all your tests with `mymod` so they can be filtered by `dribbles --tag mymod`.

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
- `skip`
- `RunMine`

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

## Test loading setup

DribbleSpec does not auto-discover consumer tests. Create a small init file for your test suite and load it explicitly when you want tests registered:

```lua
-- Shared/MyMod/Tests/_Init.lua
Ext.Require("Shared/MyMod/Tests/Smoke.test.lua")
Ext.Require("Shared/MyMod/Tests/Runtime.test.lua")
```

Then require that test init file from your mod's own debug bootstrap, dev-only init path, or other explicit entrypoint before running `dribbles`.

## Running tests

Use DribbleSpec console command:

- run all loaded tests: `dribbles` (or shorthand `d`)
- help: `dribbles --help`
- name filter: `dribbles --name "migration"`
- tag filter: `dribbles --tag runtime --tag server`
- context: `dribbles --context server`
- fail fast: `dribbles --fail-fast`

If you set `commandAlias` in `RegisterTestGlobals`, use that alias to run only your mod-owned tests:

- run only this mod: `mytests`

## Skipping tests

### Static (registration time)

```lua
D.test.skip("not ready", function() ... end)
D.describe.skip("whole suite", function() ... end)
-- or via metadata:
D.test("skip via opts", { skip = true }, function() ... end)
```

### Dynamic (runtime)

Use `D.skip(reason)` (standalone) or `ctx.skip(reason)` (inside test body) to skip based on runtime conditions:

```lua
local D = RegisterTestGlobals()

D.describe("Optional integration", { tags = { "entity" } }, function()
    D.test("resolves preplaced entity", function(ctx)
        local entity = Ext.Entity.Get(MY_GUID)
        if entity == nil then
            D.skip("Entity not in current save")
        end
        ctx.expect(entity).toBeEntity()
    end)
end)
```

`ctx.requireClient()` and `ctx.requireServer()` are shorthand skips for context guards.

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

        ctx.expect(guid).toBeUuid()
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
local run = D.RunMine({
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
  - verify your test init file is loaded before running `dribbles`.
