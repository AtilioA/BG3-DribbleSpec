# DribbleSpec Implementation Plan

This roadmap implements `SPEC.md` with JSON reporting as the final phase.

## Locked Decisions

- Command name: `dribble`.
- Caller mod display name source: `Ext.Mod.GetMod(<moduleUUID>).Info.Name`.
- Explicit include manifest name: `DribbleTests.lua`.
- Framework style: greenfield, standalone, mod-agnostic.
- Development style: no automated tests in Phase 0; strict TDD + dogfooding starts in Phase 1.
- JSON reporter: lowest priority.

## Multi-Phase Delivery Plan

### Phase 0 - Scaffold and Contracts (No Automated Tests)

Goal:
- Build the skeleton and freeze internal boundaries before feature work.

Scope:
- Create DribbleSpec folder/module scaffold.
- Implement internal contracts for registry, runner, result model, options parsing, sandbox placeholder.
- Implement command plumbing (`dribble`) and manual smoke run flow.
- Implement explicit manifest loading contract (`DribbleTests.lua`).
- Add docs updates and Context7 reference guidance.

Validation approach:
- Manual smoke checks only (no test harness yet).

Exit criteria:
- `Ext.Require("Shared/DribbleSpec/init.lua")` loads.
- `dribble` command executes and returns deterministic empty summary when no tests are registered.
- `dribble --help` prints usable options.

### Phase 1 - Minimal Runnable Framework (Start TDD Here)

Goal:
- Dribble can run its own tests.

Scope:
- Implement DSL registration basics: `describe`, `test`, `it`, `test.skip`, `test.only`.
- Implement hooks: `beforeAll`, `beforeEach`, `afterEach`, `afterAll`.
- Implement deterministic registration order.
- Create Dribble self-tests and run them through Dribble (dogfooding starts).

Exit criteria:
- Dribble self-tests can be loaded from explicit manifest and executed by `dribble`.

### Phase 2 - Runner and Filtering

Goal:
- Reliable test execution controls.

Scope:
- Full runner lifecycle and status handling (`passed|failed|skipped`).
- Filtering: `--name`, `--tag` (repeatable), `--context`.
- Run control: `--fail-fast`.

Exit criteria:
- Filter and control behavior covered by Dribble self-tests.

### Phase 3 - Expect Core

Goal:
- Usable assertion API.

Scope:
- Core matchers and throw matchers from spec.
- Deterministic deep equality and stable diffs.

Exit criteria:
- Assertion behavior and error messages covered by self-tests.

### Phase 4 - Doubles and Isolation

Goal:
- Robust stubs/spies/mocks with automatic restoration.

Scope:
- `ctx.spyOn`, `ctx.stub`, `ctx.mockFn`.
- Call assertions (`toHaveBeenCalled*`).
- Leak prevention across test boundaries.

Exit criteria:
- Isolation guarantees covered by self-tests.

### Phase 5 - Runtime Helpers

Goal:
- Runtime-aware tests in client/server contexts.

Scope:
- `ctx.requireClient`, `ctx.requireServer` with skip semantics.
- `ctx.nextTick`, `ctx.waitUntil` with timeout behavior.

Exit criteria:
- Context mismatch -> skipped (not failed), covered by self-tests.

### Phase 6 - Fixtures Framework

Goal:
- Repeatable setup/teardown for mod tests.

Scope:
- Fixture manager + provider contract.
- Provider order: pre-placed first, spawn fallback second.
- `ctx.fixture.character/item/entity`, `ctx.fixture.state.snapshot/restore`.
- Workflow convention: destructive world-mutation tests should use a dedicated `destructive` tag.

Exit criteria:
- Cleanup and restoration behavior covered by self-tests.

### Phase 7 - Entity/ECS Domain Layer

Goal:
- Reduce flakiness for entity-heavy suites.

Scope:
- `EntityRef` abstraction with lazy re-resolution.
- Domain matchers: `toBeGuid`, `toBeEntity`, `toHaveComponent`.
- Volatile-field filter presets.

Exit criteria:
- Entity lifecycle and stale-handle resilience covered by self-tests.

### Phase 8 - Consumer UX and Adoption Docs

Goal:
- Extremely easy adoption by external mods.

Scope:
- Markdown integration docs.
- Packaging guidance for dependency mods. They should be able to call a single function to register namespace into their globals table.
- Example suites for unit/runtime/entity modes. Include examples for every use case supported by DribbleSpec, as well as examples of how to extend DribbleSpec to support new use cases and tailor it to specific mod needs.

Exit criteria:
- Clean start-to-finish integration walkthrough exists.

### Phase 9 - Agent Skill

Use the skill-creator skill to create a skill to inform LLM agents on how to use DribbleSpec. Include examples of how to import and use DribbleSpec to test a mod, how to create a test file, how to run the tests.
Make sure to add examples to how to integrate with BG3 domain, i.e. how to use it for entities, handle BG3SE lifetime, etc.
This should reuse a lot of the documentation from Phase 8, but tailoring it and its examples, succintly, for LLM agents.

### Phase 10 - JSON Reporter (Lowest Priority)

Goal:
- CI artifact output.

Scope:
- JSON schema output from `SPEC.md`.
- Caller name resolution from `moduleUUID -> Info.Name`.
- Default output path:
  - `DribbleSpec/<caller_modname>/results_<file-safe_ISO8601_timestamp>.json`
- `--json-out` override.

---

Exit criteria:
- Reporter output and failure behavior covered by self-tests.

## Phase 1 Deep Dive (TDD Starts)

### A) Phase 1 Objective

- DribbleSpec can register and execute tests through public APIs.
- DribbleSpec self-tests run via `dribble` from explicit `DribbleTests.lua` includes.
- Development follows strict vertical TDD slices (no horizontal test batching).

### B) Public Behavior Contract for Phase 1

- API available: `describe`, `test`, `it`, `test.skip`, `test.only`, `beforeAll`, `beforeEach`, `afterEach`, `afterAll`.
- `beforeAll` failure policy: skip remaining tests in that suite.
- `afterEach` failure policy: fail current test only.
- Execution order is deterministic by declaration order.

### C) Vertical Slice Plan (No Horizontal Slicing)

1. Slice P1.1: single `describe` + single `test` executes and reports pass.
2. Slice P1.2: failing test reports fail message and stack.
3. Slice P1.3: `it` alias parity with `test`.
4. Slice P1.4: `test.skip` reports skipped without executing body.
5. Slice P1.5: `test.only` focus behavior (global only-mode).
6. Slice P1.6: `beforeEach` and `afterEach` run around each test in order.
7. Slice P1.7: `beforeAll` and `afterAll` run once per suite.
8. Slice P1.8: `beforeAll` failure skips remaining suite tests.
9. Slice P1.9: `afterEach` failure marks only current test failed.
10. Slice P1.10: nested `describe` order and full name composition.

Each slice rule:
- RED: write one behavior test through public API.
- GREEN: minimal implementation for that behavior only.
- REFACTOR: only while green.

### D) Dogfooding Setup

- Self-tests live under `Shared/DribbleSpec/Tests/`.
- Explicit include manifest remains `Lua/DribbleTests.lua`.
- `DribbleTests.lua` loads self-test files with `Ext.Require`.

### E) Runtime and Tooling Notes

- DribbleSpec core remains under `Shared/DribbleSpec/`.
- Client/server-only behavior is gated with `Ext.IsClient()`/`Ext.IsServer()`.
- Use `bg3se-console-ops` for console-driven iteration and log inspection during Phase 1.

### F) Phase 1 Exit Criteria

- `dribble` runs self-tests and reports correct pass/fail/skip totals.
- Hook failure policies are implemented exactly as locked.
- Deterministic ordering is proven by self-tests.
- No tests rely on internal modules or private state.

Status (2026-03-03):
- Phase 1 functional behavior slices are implemented and covered through dogfood tests.
- Phase 2 is complete: filtering (`--name`, repeatable `--tag`, `--context`) and `--fail-fast` controls are implemented and covered by self-tests.
- Phase 3 is complete: `expect` core matchers (`toBe`, `toEqual`, `toBeNil`, `toBeTruthy`, `toBeFalsy`, `toContain`, `toThrow`, `toThrowMatch`) with deterministic deep-equality diff output are implemented and covered by self-tests.
- Phase 4 is complete: doubles (`ctx.mockFn`, `ctx.spyOn`, `ctx.stub`) and call assertions (`toHaveBeenCalled*`) are implemented with per-test restoration covered by self-tests.
- Phase 5 is complete: runtime helpers (`ctx.requireClient`, `ctx.requireServer`, `ctx.nextTick`, `ctx.waitUntil`) are implemented with deterministic fallback guardrails covered by self-tests.
- Phase 6 is complete: fixture manager/provider pipeline, fixture APIs (`ctx.fixture.character/item/entity`), and state snapshot/restore cleanup guarantees are implemented and covered by self-tests.
- Phase 7 is complete: `EntityRef` lazy re-resolution, entity domain matchers (`toBeGuid`, `toBeEntity`, `toHaveComponent`), and optional `toEqual(..., { volatilePreset = "entity" })` filtering are implemented and covered by self-tests.
- Phase 8 is complete: consumer UX layer adds centralized public symbol registry and global `RegisterTestGlobals()` table-export entrypoint with consolidated adoption docs.
- Phase 9 is complete: repo-local `dribblespec` agent skill was added with BG3/DribbleSpec usage guidance, examples, eval prompts, and a script to symlink it into user-global skills.
- Client runtime dogfood run observed with totals `passed=31 failed=0 skipped=1 total=32`.
- Server-context execution remains available through NetChannel routing for `--context server` from client sessions.

## Phase 0 Deep Dive

## A) Internal Contracts to Freeze

### Result Model Contract
- Run summary fields always present.
- Suite/test result containers always present.
- Status vocabulary fixed: `passed|failed|skipped` for tests; run-level derived from summary.

### Registry Contract
- Deterministic insertion order index.
- Suite/test nodes carry metadata bag even before full DSL implementation.

### Runner Contract
- Input: registry snapshot + normalized options.
- Output: deterministic run result object.
- Must not mutate declaration metadata.

### Options Contract
- Parse console args into normalized options table.
- Unknown args preserved for diagnostics.

### Command Contract
- `dribble` calls parse -> manifest load -> run.
- Help path exits without running.

## B) Phase 0 Build Tasks

1. Scaffold module tree:
- `init.lua`
- `Core/Registry.lua`
- `Core/ResultModel.lua`
- `Runner/Runner.lua`
- `Runner/Options.lua`
- `Internal/Clock.lua`
- `Internal/Sandbox.lua`
- `Internal/CallerMod.lua`
- `Internal/ManifestLoader.lua`

2. Implement minimal wiring:
- init module creates singleton registry instance.
- run path can execute empty registry and return stable result.

3. Implement command plumbing:
- register `dribble` once.
- parse and print help/options/summary.

4. Implement explicit include-manifest behavior:
- default manifest `DribbleTests.lua`.
- safe loading with warning on missing manifest.

5. Documentation updates:
- keep `SPEC.md` and this plan aligned.
- include Context7 lookup reminder in spec.

## C) Phase 0 Manual Smoke Checklist

- Load check: require DribbleSpec init module.
- Help check: run `dribble --help`.
- Empty run check: run `dribble` with no manifest present and verify deterministic zero-summary output.
- Manifest check: run `dribble --manifest <path>` with a valid file and verify load path is used.

## D) Risks and Mitigations

- Risk: early API churn.
  - Mitigation: freeze internal contracts now, public features later.
- Risk: command double-registration during reload.
  - Mitigation: global guard around console command registration.
- Risk: hidden assumptions about BG3SE APIs.
  - Mitigation: use Context7 lookup when uncertain and document constraints.

## E) Immediate Next Step

Execute Phase 0 scaffold implementation now, then run manual smoke checks.

## Unresolved Questions

- None.
