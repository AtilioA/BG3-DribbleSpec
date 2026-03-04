# DribbleSpec Phase 0 Notes

Phase 0 intentionally does not include an automated test harness.

## Manual Smoke Checks

1. Load the framework module:
   - `Ext.Require("Shared/DribbleSpec/init.lua")`
2. Confirm command help:
   - `dribbles --help`
3. Confirm empty run path:
   - `dribbles`
4. Confirm manifest argument path is accepted:
   - `dribbles --manifest DribbleSpecTests.lua`

## Current Behavior

- Command `dribbles` is registered on framework load.
- Default include manifest is `DribbleSpecTests.lua`.
- Missing manifest is treated as a warning in Phase 0.
- Phase 1 implemented runnable DSL and hook execution; see `Docs/PHASE1_PLAN.md` for active TDD scope.

## Next Step

Continue Phase 1 vertical TDD slices and expand dogfood coverage.
