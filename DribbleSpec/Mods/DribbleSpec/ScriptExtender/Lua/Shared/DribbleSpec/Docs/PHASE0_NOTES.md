# DribbleSpec Phase 0 Notes

Phase 0 intentionally does not include an automated test harness.

## Manual Smoke Checks

1. Load the framework module:
   - `Ext.Require("Shared/DribbleSpec/init.lua")`
2. Confirm command help:
   - `dribble --help`
3. Confirm empty run path:
   - `dribble`
4. Confirm manifest argument path is accepted:
   - `dribble --manifest DribbleTests.lua`

## Current Behavior

- Command `dribble` is registered on framework load.
- Default include manifest is `DribbleTests.lua`.
- Missing manifest is treated as a warning in Phase 0.
- DSL methods (`describe/test/hooks`) are placeholders until Phase 1.

## Next Step

Phase 1 starts strict TDD and dogfooding with DribbleSpec self-tests.
