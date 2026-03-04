# DribbleSpec Troubleshooting

## `RegisterTestGlobals` issues

- Symptom: `RegisterTestGlobals` is nil.
- Cause: DribbleSpec not loaded before consumer test file executes.
- Fix: ensure bootstrap/load order includes DribbleSpec first.

## No tests execute

- Symptom: `dribble` runs with zero selected tests.
- Common causes:
  - include file not loaded
  - filters exclude all tests (`--name`, `--tag`, `--context`)
  - tests not tagged as expected
- Fix: run without filters, then add filters incrementally.

## Entity `DisplayName` flakiness

- Symptom: component shape differs or matcher fails in client context.
- Fix: move assertions to server context (`ctx.requireServer()`, `--context server`).

## DAP `pause failed` while running commands

- Symptom: evaluate command returns `pause failed` but command may still have started.
- Fix:
  1. execute command
  2. read latest runtime log output separately
  3. rerun after VM reset if needed

## Stale entity handle behavior

- Symptom: direct entity userdata becomes invalid across ticks/lifecycle transitions.
- Fix: use `ctx.entityRef(...)` / `D.entityRef(...)` and resolve late.
