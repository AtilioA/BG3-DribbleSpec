# dribblespec-mutate

Mutation testing host for DribbleSpec mods.

Setup (from `tools/mutation/`):

    uv sync
    uv pip install -e C:/Users/AAD/Git/llm-skills/.agents/skills/bg3se-console-ops/bg3se-console-mcp

`uv sync` removes the broker again; repeat the second command after it. `list` and the tests do not need the broker.

    uv run dribblespec-mutate list --config <mutation.config.json>   # plan and patch chunks, offline
    uv run dribblespec-mutate run --config <mutation.config.json>    # game running: statuses and summary
    uv run pytest
