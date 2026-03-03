# AGENTS.md

Project type: BG3 Script Extender (Lua) framework mod.
Purpose: reusable test framework for BG3SE mods.

Commit and push autonomously: stage only related changes together; each commit must represent one logical, self-contained change. Write as in conventional commits: <type>: <what and why>. This keeps history bisectable and every commit safely revertable.

### Test execution (BG3SE console)

Use the bg3se-console-ops skill to access the SE console and run tests, or read logs.

- Main framework/test command:
  - `dribble`
- Show options/help:
  - `dribble --help`
- Run a single test (name match):
  - `dribble --name "<test name or pattern>"`
- Run subset by tag:
  - `dribble --tag runtime`
Etc.

## Required TDD Workflow

Use the tdd skill to implement the TDD workflow.

## Coding Style Conventions (Lua/BG3SE)

### Imports and module structure

- Use `Ext.Require("Shared/.../file.lua")` style paths from Lua root.
- Prefer local module imports at top of file.
- Return module table at end for library modules.
- Keep side-effectful registration explicit (`_Init.lua`, command registration, event subscriptions).

### Naming

- Module tables/classes: PascalCase (`Registry`, `ResultModel`, `Runner`).
- Methods on module/class tables: PascalCase in this codebase (`AddSuite`, `Finalize`, `ParseArgs`).
- Local variables/functions: `camelCase` if already established;
- Globals should be intentional and sparse (`Dribble`, `RequireFiles`, print helpers).
- Constants: uppercase-like field names where already established (`DEFAULT_MANIFEST_PATH`).

### Formatting

- Keep lines readable; avoid dense one-liners except trivial wrappers.
- Prefer early returns for guards.

### Types and annotations

- Always use EmmyLua annotations for public and internal contracts:
  - `---@class`, `---@field`, `---@param`, `---@return`.
- Annotate non-trivial public APIs and core data models.

### Error handling and resilience

- Validate inputs with `type(...)` checks at boundaries, or use Ext.Types.
- Use `pcall` around risky runtime interactions (`Ext.Require`, external API calls). Always cover success and failure paths.
- Convert non-fatal failures to warnings when appropriate.
- Keep deterministic result shapes even on partial failures.

### Logging and diagnostics

- Prefer `Ext.Utils.Print` / `Ext.Utils.PrintWarning`.
- Keep logs actionable and concise.
- Include context in warnings (path, option, UUID, phase).

### Shared/client/server boundaries

- Put cross-context logic in `Shared/DribbleSpec/`.
- Gate context-specific behavior with `Ext.IsClient()` / `Ext.IsServer()`.

### State and side effects

- Keep module-level mutable state minimal and intentional.
- Use explicit reset points for registries/singletons where needed.
- Guard one-time command registration to avoid duplicate handlers on reload.

## Testing-Specific Semantics (locked)

- If `beforeAll` fails for a suite: mark remaining suite tests as `skipped`.
- If `afterEach` fails: fail current test only; continue unless fail-fast is enabled.

## Agent Operational Notes

- Use `bg3se-console-ops` for iterative BG3SE console/test output workflows.
- Do not add speculative framework features ahead of active TDD slice.
- If uncertain about BG3SE API, use the Context7 MCP.
- Commit and push often! Create semantic commits whenever possible.

## Surprise Log Policy

If you hit unexpected runtime behavior, add a short “Surprise note” here with:

- Date, what happened, trigger/context, safe workaround/solution.

Keep notes concise so future agents avoid repeated failure modes.

Surprise note (2026-03-02): If `Shared/DribbleSpec/init.lua` tries to preload `DribbleTests.lua` during its own module initialization, test files that `Ext.Require("Shared/DribbleSpec/init.lua")` can recurse and hit `too many C levels`. Safe workaround: set `_G.Dribble` early and have test files use `_G.Dribble or Ext.Require(...)`.
When following Red-Green-Refactor, make sure to run the tests after EACH step with `bg3se-console-ops`. You have to validate that the tests are actually running, then that the implementation fixes them, and then that the refactoring does not break them.
