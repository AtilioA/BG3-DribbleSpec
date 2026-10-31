# dribblespec-mutate

Mutation testing host for DribbleSpec mods.

Setup (from `tools/mutation/`):

    uv sync
    uv pip install -e C:/Users/AAD/Git/llm-skills/.agents/skills/bg3se-console-ops/bg3se-console-mcp

`uv sync` removes the broker again; repeat the second command after it. `list` and the tests do not need the broker.

    uv run dribblespec-mutate list --config <mutation.config.json>   # plan and patch chunks, offline
    uv run dribblespec-mutate run --config <mutation.config.json>    # game running: statuses and summary
    uv run pytest

Config (paths relative to the config file):

    {
      "mod": "Mod Configuration Menu/Mods/BG3MCM",
      "files": ["Shared/Helpers/Validators/*.lua"],
      "testFilter": { "tags": ["validators"] },
      "ignoreCalls": ["MCMPrint"]
    }

`mod` is the `Mods/<Folder>` directory. `files` are globs under `<mod>/ScriptExtender/Lua`. The mod table comes from `<mod>/ScriptExtender/Config.json` (`ModTable`); in game the agent takes the ModuleUUID and the deployed directory from that loaded mod. The tests to run must be owned by that ModuleUUID. `testFilter` (`tags`, `name`) and `ignoreCalls` are optional.
