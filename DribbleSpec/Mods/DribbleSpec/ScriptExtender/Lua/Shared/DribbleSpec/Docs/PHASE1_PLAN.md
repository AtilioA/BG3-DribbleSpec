# DribbleSpec Phase 1 Plan

Phase 1 starts strict TDD and dogfooding.

## Locked Behavior

- Public API: `describe`, `test`, `it`, `test.skip`, `test.only`, hooks.
- `beforeAll` failure => remaining tests in suite are `skipped`.
- `afterEach` failure => current test is `failed` only.
- Deterministic execution order by declaration order.

## TDD Rules

- Vertical slices only (no horizontal batching).
- One behavior test at a time through public API.
- Minimal implementation to turn RED to GREEN.
- Refactor only while GREEN.

## Slice Sequence

1. single passing test execution.
2. single failing test reporting.
3. `it` alias behavior.
4. `test.skip` behavior.
5. `test.only` behavior.
6. `beforeEach`/`afterEach` ordering.
7. `beforeAll`/`afterAll` once-per-suite.
8. `beforeAll` failure skip semantics.
9. `afterEach` failure current-test semantics.
10. nested suite naming/order.

## Dogfood Setup

- Self-tests location: `Shared/DribbleSpec/Tests/`.
- Explicit manifest: `Lua/DribbleTests.lua`.
- Runner command: `dribble`.

## Iteration

- Use `bg3se-console-ops` for console iteration, output checks, and runtime logs.
