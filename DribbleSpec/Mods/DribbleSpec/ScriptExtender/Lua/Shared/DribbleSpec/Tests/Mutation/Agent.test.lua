local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local Agent = Ext.Require("Shared/DribbleSpec/Mutation/Agent.lua")
local Registry = Ext.Require("Shared/DribbleSpec/Core/Registry.lua")
local Runner = Ext.Require("Shared/DribbleSpec/Runner/Runner.lua")
local Options = Ext.Require("Shared/DribbleSpec/Runner/Options.lua")
local SkipSignal = Ext.Require("Shared/DribbleSpec/Runtime/SkipSignal.lua")
Ext.Require("Shared/DribbleSpec/Tests/Mutation/Fixture.lua")

local RUN_ID = "selftest-agent"
local DIR = "DribbleSpecMutation/" .. RUN_ID .. "/"
local PATCH = DIR .. "1.lua"
local FIXTURE_DIR = "Mods/DribbleSpec/ScriptExtender/Lua/Shared/DribbleSpec/Tests/Mutation/"
-- Pinned hash of Fixture.lua; tools/mutation/tests/test_fixture.py checks it and Fixture.patch.txt.
local FIXTURE_HASH = "74478c78"
local ABOVE = "Fixture IsAtLeast is true above the minimum"
local OTHER = "Fixture other does not call the target"
local SKIPS = "Fixture skips skips when IsAtLeast is wrong"
local HOOK_TEST = "Fixture hook runs after beforeAll"
local HOOK = "Fixture hook [hook] beforeAll"

---@param sourceHash string
local function writePlan(sourceHash)
    Ext.IO.SaveFile(PATCH, Ext.IO.LoadFile(FIXTURE_DIR .. "Fixture.patch.txt", "data"))
    Ext.IO.SaveFile(DIR .. "coverage.jsonl", "")
    Ext.IO.SaveFile(DIR .. "results.jsonl", "")
    Ext.IO.SaveFile(DIR .. "plan.json", Ext.Json.Stringify({
        schemaVersion = 1,
        runId = RUN_ID,
        ownerModuleUUID = "",
        modTable = "Dribbles",
        modDirectory = "DribbleSpec",
        testFilter = { name = "Fixture " },
        files = { {
            index = 1,
            path = "Shared/DribbleSpec/Tests/Mutation/Fixture.lua",
            sourceHash = sourceHash,
            patchPath = PATCH,
            targets = { "MutationFixture.IsAtLeast" },
        } },
        mutants = {},
    }))
end

---@return MutationAgent
local function createAgent()
    local registry = Registry.Create()
    registry:BeginSuite("Fixture")
    registry:BeginSuite("IsAtLeast")
    registry:AddTest("is true above the minimum", {}, function()
        Assertions.Equals(MutationFixture.IsAtLeast(5, 1), true, "IsAtLeast(5, 1)")
    end)
    registry:EndSuite()
    registry:BeginSuite("other")
    registry:AddTest("does not call the target", {}, function() end)
    registry:EndSuite()
    registry:BeginSuite("skips")
    registry:AddTest("skips when IsAtLeast is wrong", {}, function()
        if not MutationFixture.IsAtLeast(5, 1) then
            SkipSignal.Throw("IsAtLeast is wrong")
        end
    end)
    registry:EndSuite()
    registry:BeginSuite("hook")
    registry:AddHook("beforeAll", function()
        Assertions.Equals(MutationFixture.IsAtLeast(5, 1), true, "IsAtLeast(5, 1) in beforeAll")
    end)
    registry:AddTest("runs after beforeAll", {}, function() end)
    registry:EndSuite()
    registry:EndSuite()
    return Agent.Create({
        registry = registry,
        run = function(options)
            return Runner.Run({ registry = registry, options = Options.Normalize(options), clock = { NowMs = function() return 0 end } })
        end,
    })
end

---@param name string
---@return table[]
local function readLines(name)
    local lines = {}
    for line in (Ext.IO.LoadFile(DIR .. name) or ""):gmatch("[^\n]+") do
        table.insert(lines, Ext.Json.Parse(line))
    end
    return lines
end

DribbleSpec.describe("DribbleSpec Mutation agent", { tags = { "mutation" } }, function()
    local original = MutationFixture.IsAtLeast
    local agent

    DribbleSpec.beforeEach(function()
        agent = createAgent()
    end)

    DribbleSpec.afterEach(function()
        agent.Restore(RUN_ID)
    end)

    DribbleSpec.test("Prepare installs the patch and writes the test list", function()
        writePlan(FIXTURE_HASH)
        Assertions.Equals(agent.Prepare(RUN_ID), "ok", "Prepare")
        Assertions.Equals(MutationFixture.IsAtLeast ~= original, true, "patched")
        Assertions.Equals(Ext.IO.LoadFile(DIR .. "tests.json"),
            Ext.Json.Stringify({ ABOVE, OTHER, SKIPS, HOOK_TEST }, { Beautify = false }), "tests.json")
    end)

    DribbleSpec.test("DryRun records hits only for the test that calls the target", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Equals(agent.DryRun(RUN_ID, { ABOVE, OTHER }), "ok", "DryRun")
        local lines = readLines("coverage.jsonl")
        Assertions.Equals(#lines, 2, "coverage lines")
        Assertions.Equals(table.concat(lines[1].hits, ","), "1,2", "hits of " .. ABOVE)
        Assertions.Equals(#lines[2].hits, 0, "hits of " .. OTHER)
    end)

    DribbleSpec.test("DryRun raises for a selected test that did not run", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Equals(agent.DryRun(RUN_ID, { "Fixture missing" }), "error: test not run: Fixture missing", "DryRun")
    end)

    DribbleSpec.test("statuses escape non-ASCII bytes", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Equals(agent.DryRun(RUN_ID, { "Fixture caf\195\169" }),
            "error: test not run: Fixture caf\\195\\169", "DryRun")
    end)

    DribbleSpec.test("a Prepare that cannot write tests.json leaves nothing installed", function()
        writePlan(FIXTURE_HASH)
        local blockedDir = "DribbleSpecMutation/selftest-blocked/"
        for _, name in ipairs({ "plan.json", "1.lua" }) do
            Ext.IO.SaveFile(blockedDir .. name, Ext.IO.LoadFile(DIR .. name))
        end
        Ext.IO.SaveFile(blockedDir .. "plan.json",
            (Ext.IO.LoadFile(blockedDir .. "plan.json"):gsub(RUN_ID, "selftest-blocked")))
        -- A directory named tests.json makes SaveFile fail.
        Ext.IO.SaveFile(blockedDir .. "tests.json/blocker", "")
        Assertions.Equals(agent.Prepare("selftest-blocked"),
            "error: cannot write DribbleSpecMutation/selftest-blocked/tests.json", "Prepare")
        Assertions.Equals(MutationFixture.IsAtLeast, original, "not patched")
        Assertions.Equals(agent.Prepare(RUN_ID), "ok", "a later Prepare is not refused")
    end)

    DribbleSpec.test("RunMutant classifies Survived and Killed", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Equals(agent.RunMutant(RUN_ID, 1, { ABOVE }), "ok", "RunMutant 1")
        Assertions.Equals(agent.RunMutant(RUN_ID, 2, { ABOVE }), "ok", "RunMutant 2")
        local lines = readLines("results.jsonl")
        Assertions.Equals(lines[1].status, "Survived", ">= to >")
        Assertions.Equals(lines[2].status, "Killed", ">= to <")
        Assertions.Equals(lines[2].killedBy[1], ABOVE, "killedBy")
        Assertions.Equals(lines[2].attempt, 1, "attempt")
        Assertions.Contains(lines[2].message, "IsAtLeast(5, 1): expected true, got false", "failure message")
        Assertions.NotContains(lines[2].message, "\n", "first line only")
        Assertions.Equals(MutationFixture.IsAtLeast(1, 5), false, "no active mutant after the run")
    end)

    DribbleSpec.test("RunMutant classifies skipped tests without a failure as RuntimeError", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        agent.RunMutant(RUN_ID, 2, { SKIPS })
        local line = readLines("results.jsonl")[1]
        Assertions.Equals(line.status, "RuntimeError", "status")
        Assertions.Equals(line.skipped, 1, "skipped")
    end)

    DribbleSpec.test("RunMutant classifies a failing beforeAll as Killed", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        agent.RunMutant(RUN_ID, 1, { HOOK_TEST })
        agent.RunMutant(RUN_ID, 2, { HOOK_TEST })
        local lines = readLines("results.jsonl")
        Assertions.Equals(lines[1].status, "Survived", "hook passes under >= to >")
        Assertions.Equals(lines[2].status, "Killed", "hook fails under >= to <")
        Assertions.Equals(lines[2].killedBy[1], HOOK, "killedBy")
    end)

    DribbleSpec.test("Restore reinstalls the original function", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Equals(agent.Restore(RUN_ID), "ok", "Restore")
        Assertions.Equals(MutationFixture.IsAtLeast, original, "original back")
    end)

    DribbleSpec.test("a second Prepare while patches are active is refused", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Contains(agent.Prepare(RUN_ID), "error: patches are active", "second Prepare")
    end)

    DribbleSpec.test("a hash mismatch stops Prepare before any install", function()
        writePlan("00000000")
        Assertions.Equals(agent.Prepare(RUN_ID),
            "error: deployed source differs from repo: Shared/DribbleSpec/Tests/Mutation/Fixture.lua", "Prepare")
        Assertions.Equals(MutationFixture.IsAtLeast, original, "not patched")
    end)
end)
