---
name: dribblespec
description: Use this skill whenever a request involves BG3SE mod testing with DribbleSpec: creating or migrating tests, wiring `RegisterTestGlobals()`, using `describe/test/expect`, running `dribble` filters, debugging runtime or entity failures, or fixing client/server flakiness. Trigger even if the user only says "BG3 tests" or "dribble". Skip this skill for unrelated gameplay features or general Lua code with no test setup/execution work.
---

# DribbleSpec Agent Skill

Use this skill to implement and maintain tests for mods that depend on DribbleSpec.

## When to use

Use this skill whenever the task involves any of:

- creating or updating DribbleSpec test suites
- wiring consumer tests with `RegisterTestGlobals()`
- writing runtime/entity assertions for BG3SE behavior
- running tests via `dribble` and diagnosing failures
- reducing flaky behavior due to BG3SE context/lifecycle issues

If the user asks for BG3 mod testing and does not mention a framework, still use this skill and standardize on DribbleSpec patterns.

## Core contract (must follow)

- `RegisterTestGlobals()` takes no arguments and returns a table of exports.
- Assign returned exports in consumer code, for example:

```lua
local D = RegisterTestGlobals()
```

- Do not assume framework-side mutation of `Mods.Dribbles`.
- Use explicit include model for test files (`Ext.Require(...)`), no implicit discovery.

## Standard workflow for agents

1. Confirm/create test entrypoint include file(s) with explicit `Ext.Require` calls.
2. In each test file, import Dribble globals table once (`local D = RegisterTestGlobals()`).
3. Write tests via public API (`D.describe`, `D.test`, hooks, `ctx` helpers).
4. Run targeted tests first (`--name` or `--tag`) then broader run.
5. Fix failures through behavior assertions, not internal implementation coupling.
6. Keep runtime/entity tests context-safe (`ctx.requireClient` / `ctx.requireServer`).

Use vertical TDD slices when implementing features or bugfixes.

## Consumer scaffolding

### Minimal test file

```lua
local D = RegisterTestGlobals()

D.describe("MyMod smoke", { tags = { "unit" } }, function()
    D.test("basic expectation", function()
        D.expect(true).toBeTruthy()
    end)
end)
```

### Test include file (explicit)

```lua
Ext.Require("Shared/MyMod/Tests/Smoke.test.lua")
Ext.Require("Shared/MyMod/Tests/Runtime.test.lua")
```

## CLI execution patterns

- all tests: `dribble`
- help: `dribble --help`
- one area: `dribble --name "phase8"`
- subset by tags (AND): `dribble --tag runtime --tag server`
- force context filter: `dribble --context server`
- stop early: `dribble --fail-fast`

## BG3 domain guidance

### Entity assertions

- Use domain matchers when possible: `toBeGuid`, `toBeEntity`, `toHaveComponent`.
- Prefer `entityRef` for stale-handle resilience in longer flows.

### Entity userdata lifetime (Context7-verified)

- BG3SE `userdata` objects are scope/lifetime-bound; they are valid during current Lua call, but may expire afterwards.
- Avoid caching component userdata (or nested userdata like `entity.SpellBook.Spells[...]`) across ticks/events.
- Accessing expired userdata can raise errors like: `Attempted to read object ... whose lifetime has expired`.
- Persist stable identity only (GUID / NetId), then re-resolve when needed (`ctx.entityRef(...)` / `D.entityRef(...)`, or fresh `Ext.Entity.Get(...)`). DribbleSpec provides `ctx.entityRef` and `D.entityRef` helpers for this, and will automatically resolve GUIDs to entities when needed (instead of caching expired handles).
- Before deeper reads in delayed callbacks, prefer an alive check (`entity:IsAlive()`), then re-fetch component data.
- `entity:GetComponent(name)` returns `nil` when missing; treat missing components as expected branch, not crash path.

Incorrect pattern (cache nested userdata across ticks):

```lua
local spells = Ext.Entity.Get(guid).SpellBook.Spells
Ext.OnNextTick(function()
    local spellId = spells[1].SpellUUID -- lifetime-risky
end)
```

### Context-sensitive component checks

- `DisplayName` assertions are reliable in server context.
- For such tests, gate with `ctx.requireServer()`.

### Optional integration behavior

When a required preplaced entity is unavailable in current runtime/save, skip clearly rather than failing.

## Runtime reliability guidance

- After script edits, reload VM before runtime test verification.
- DAP evaluate can intermittently return `pause failed` while command still runs.
- If command/eval output is partial, execute then read latest log output separately.

## Assertion strategy

- Prefer semantic behavior checks over large snapshot equality.
- Use `toEqual(..., { volatilePreset = "entity" })` only when unstable runtime fields create noise.
- Do not use volatile filtering to mask meaningful behavioral mismatches.

## Fixtures and cleanup

- Use `ctx.fixture.entity/item/character` for setup.
- Use `ctx.fixture.state.snapshot/restore` for deterministic rollback of supported state.
- Tag intentionally world-mutating tests with `destructive` so they can be selectively run.

## References

- Read `references/templates.md` for copy-paste patterns.
- Read `references/commands.md` for command matrix.
- Read `references/troubleshooting.md` when diagnosing runtime issues.
