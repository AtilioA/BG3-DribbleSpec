# DribbleSpec Specification (V1)

Standalone BG3 Script Extender (BG3SE) Lua testing framework for any mod.

## 1) Vision

DribbleSpec is a reusable test framework mod dependency, not tied to MCM or any single project.

Goals:
- Jest-like test authoring API in Lua.
- Clean isolation and developer ergonomics.
- First-class support for stubs, spies, mocks, fakes, and fixtures.
- Reliable behavior testing for BG3SE runtime code, including entity/ECS concerns.
- CI-friendly JSON output.

Non-goals for V1:
- No legacy compatibility bridge. This is a greenfield project.
- No JUnit reporter.
- No implicit folder auto-discovery.

## 2) Scope

V1 provides three suite styles under one runner:
- `unit`: pure Lua tests with fakes/doubles.
- `runtime`: BG3SE integration tests (real `Ext` APIs, minimal world assumptions).
- `entity`: scenario tests that touch real entities/world state.

Common tags for filtering:
- `client`, `server`, `unit`, `runtime`, `entity`, `slow`, `flaky`.

## 3) Package and Layout

Location in this repo:
- `DribbleSpec/Mods/DribbleSpec/ScriptExtender/Lua/Shared/DribbleSpec/`

Runtime layout rules:
- `Shared/` code runs on both client and server.
- `Client/` is client-only.
- `Server/` is server-only.
- DribbleSpec core lives in `Shared/DribbleSpec/` and gates context-specific behavior with `Ext.IsClient()`/`Ext.IsServer()`.

Proposed internal structure:
- `init.lua` - public API export.
- `Core/` - registry, lifecycle, metadata.
- `Runner/` - execution engine, filtering, timing.
- `Expect/` - assertions and deep equality.
- `Doubles/` - spies/stubs/mocks/fakes + sandbox restoration.
- `Fixtures/` - provider contracts, fixture manager, cleanup tracker.
- `Runtime/` - client/server guards, async utilities.
- `Reporters/JsonReporter.lua` - JSON result emitter.
- `Docs/` - consumer docs and examples.

## 4) Public API (Jest-like)

### 4.1 Suite/Test DSL

Required API:
- `describe(name, fn)`
- `describe(name, opts, fn)` where `opts.tags` is supported.
- `test(name, fn)`
- `test(name, opts, fn)` where `opts.tags`, `opts.timeoutTicks` are supported.
- `it(...)` alias for `test(...)`.
- `test.skip(...)`
- `test.only(...)`

### 4.2 Lifecycle Hooks

Required hooks:
- `beforeAll(fn)`
- `beforeEach(fn)`
- `afterEach(fn)`
- `afterAll(fn)`

Hook context (`ctx`) includes sandbox, fixtures, runtime helpers, and expect/doubles helpers.

### 4.3 Expectations

Core matchers:
- `expect(value).toBe(expected)`
- `expect(value).toEqual(expected[, opts])`
- `expect(value).toBeNil()`
- `expect(value).toBeTruthy()`
- `expect(value).toBeFalsy()`
- `expect(value).toContain(item)`

Error matchers:
- `expect(fn).toThrow()`
- `expect(fn).toThrowMatch(pattern)`

BG3 domain matchers:
- `expect(value).toBeGuid()`
- `expect(value).toBeEntity()`
- `expect(entity).toHaveComponent(name)`

Deep equality rules:
- Table-aware and userdata-safe.
- Stable diffs for failure messages.
- Optional transient-field filtering for volatile BG3 runtime fields.
- `opts.volatilePreset` supports named ignore presets (eg. `"entity"`) when strict equality would be noisy.

### 4.4 Doubles API

Required API:
- `ctx.spyOn(target, methodName)`
- `ctx.stub(target, methodName, impl)`
- `ctx.mockFn([impl])`

Spy assertions:
- `expect(spy).toHaveBeenCalled()`
- `expect(spy).toHaveBeenCalledTimes(n)`
- `expect(spy).toHaveBeenCalledWith(...)`
- `expect(spy).toHaveBeenCalledWithMatch(tableSubset)`

Isolation:
- All replacements are tracked in a per-test sandbox.
- Automatic restoration in `afterEach`, even on failure.

### 4.5 Runtime Helpers

Required helpers:
- `ctx.requireClient()` -> marks test skipped if not in client context.
- `ctx.requireServer()` -> marks test skipped if not in server context.
- `ctx.nextTick()` -> waits until next tick boundary.
- `ctx.waitUntil(predicate, opts)` where `opts.timeoutTicks` is required.

Skip semantics:
- Context mismatch is `skipped`, not `failed`.

## 5) Entity and ECS Handling

### 5.1 EntityRef Abstraction

DribbleSpec should expose an `EntityRef` helper:
- Stores stable identity (`GUID`/`NetId`/lookup descriptor).
- Resolves actual runtime entity lazily at assertion/use time.
- Reduces stale userdata handling issues in long-running tests.

### 5.2 Assertion Strategy

Guidelines:
- Prefer behavior assertions and semantic checks over full component snapshot equality.
- Support targeted component assertions (`has component`, selected fields, predicates).
- Provide opt-in strict deep checks where needed.

### 5.3 Volatile State Filters

Built-in ignore/filter support for known unstable fields:
- volatile IDs, timers, transient replication fields, and non-deterministic runtime internals.

## 6) Fixtures

### 6.1 Provider Pipeline

Default fixture provider order in V1:
1. Pre-placed/map provider.
2. Spawn provider fallback.

This order is required.

### 6.2 Fixture API

Required surface:
- `ctx.fixture.character(aliasOrSpec)`
- `ctx.fixture.item(aliasOrSpec)`
- `ctx.fixture.entity(aliasOrSpec)`
- `ctx.fixture.state.snapshot(spec)`
- `ctx.fixture.state.restore()`

Provider contract:
- Returns resource handles with teardown metadata.
- Registers all mutable operations for deterministic cleanup.

### 6.3 Cleanup Guarantees

After each test:
- spawned entities/items cleaned up;
- modified state restored from snapshot;
- test-added subscriptions/listeners removed (when possible via wrappers).

Workflow convention:
- tests that intentionally mutate live world state (eg. real deletions) should use a dedicated `destructive` tag so consumers can opt in explicitly (`dribbles --tag destructive`).

## 7) Runner and Filtering

### 7.1 Execution Model

Runner behavior:
- deterministic suite/test ordering;
- explicit include model (test files must be loaded intentionally);
- per-test timing;
- continue-on-failure by default;
- optional fail-fast mode.
- if `beforeAll` fails for a suite, remaining tests in that suite are marked `skipped` with setup-failure reason.
- if `afterEach` fails, only the current test is marked `failed` (or remains failed); later tests continue unless fail-fast is enabled.

### 7.2 Filtering

Required filters:
- by name/pattern (`--name`);
- by tag (`--tag`, repeatable);
- by context (`--context client|server|any`).

### 7.3 Console Entry

Framework-owned command namespace:
- `dribbles`

Expected options:
- `--name <pattern>`
- `--tag <tag>` (repeatable)
- `--context <client|server|any>`
- `--fail-fast`
- `--json-out <json_filename>`

## 8) JSON Reporter (V1 only reporter)

### 8.1 Default Output Path

If `--json-out` is omitted, DribbleSpec writes to:
- `DribbleSpec/<caller_modname>/results_<file-safe_ISO8601_timestamp>.json`

`<caller_modname>` is the invoking/consumer mod identifier (human-readable mod name preferred).

### 8.2 JSON Schema (V1)

Top-level:
- `framework`: string (`DribbleSpec`)
- `version`: string
- `runId`: string
- `startedAt`: ISO8601 string
- `finishedAt`: ISO8601 string
- `durationMs`: number
- `context`: `client|server|unknown`
- `filters`: object
- `summary`: object (`passed`, `failed`, `skipped`, `total`)
- `suites`: array of suite results

Suite result:
- `name`: string
- `tags`: string[]
- `durationMs`: number
- `tests`: array of test results

Test result:
- `name`: string
- `fullName`: string
- `status`: `passed|failed|skipped`
- `tags`: string[]
- `durationMs`: number
- `error`: `{ message, stack } | null`
- `skipReason`: string | null

### 8.3 CI Behavior

Exit/result policy:
- any failed test => failing run status;
- skipped tests do not fail run;
- malformed reporter write is treated as runner failure.

## 9) Mod-Agnostic Integration Contract

DribbleSpec must remain mod-agnostic:
- no direct references to MCM globals or MCM-specific services;
- only BG3SE runtime primitives (`Ext`, `Osi`) and DribbleSpec APIs;
- consumer mods opt in by loading DribbleSpec and registering tests.

Consumer namespace convenience:
- DribbleSpec exposes global `RegisterTestGlobals()`.
- `RegisterTestGlobals()` returns a table of test globals so consumer mods can assign it to their own namespace (eg. `Mods.Dribbles = RegisterTestGlobals()`).

## 10) Example Consumer Usage

```lua
local DribbleSpec = Ext.Require("Shared/DribbleSpec/init.lua")

DribbleSpec.describe("Settings migration", { tags = { "runtime", "client" } }, function()
    DribbleSpec.beforeEach(function(ctx)
        ctx.requireClient()
    end)

    DribbleSpec.test("marks migration handled", function(ctx)
        local fn = ctx.mockFn(function() return true end)
        ctx.expect(fn()).toBe(true)
        ctx.expect(fn).toHaveBeenCalledTimes(1)
    end)
end)
```

## 11) Implementation Phases

V1 phased delivery:
1. Phase 0 scaffold only (no automated tests): module structure, internal contracts, command plumbing, and manual smoke checks.
2. Core DSL + registry + hooks + skip/only.
3. Runner + filters + timing + fail-fast.
4. Expect API + deep equality/diffing.
5. Doubles + sandbox auto-restore.
6. Fixtures (pre-placed first, spawn fallback) + cleanup manager.
7. Runtime async/context helpers.
8. Entity/ECS domain helpers and matchers.
9. Docs and sample suites for consumer mods.
10. JSON reporter + default output path behavior (lowest priority).

## 12) Context7 Reference

Use Context7 as a reference source for BG3SE runtime/API details while implementing DribbleSpec.

Guidelines:
- Prefer Context7 lookup before introducing assumptions about `Ext`, `Osi`, entity behavior, or runtime hooks.
- Record relevant Context7-derived constraints in code comments or docs when they affect framework behavior.
- Re-check Context7 during entity/fixture/runtime phases when API semantics are uncertain.
- Do not hardcode behavior that contradicts known BG3SE runtime constraints.

## 13) Open Decisions (for implementation kickoff)

Resolved decisions:
- Greenfield implementation.
- Standalone reusable framework for any SE mod.
- JSON reporter only in V1.
- Fixture provider order: pre-placed first, spawn fallback.
- Explicit test includes in V1 (no auto-discovery).
- Console command name: `dribbles`.
- Explicit include manifest filename: `DribbleSpecTests.lua`.
- Caller display name resolution: `Ext.Mod.GetMod(<moduleUUID>).Info.Name`.
