local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local Agent = Ext.Require("Shared/DribbleSpec/Mutation/Agent.lua")
local Registry = Ext.Require("Shared/DribbleSpec/Core/Registry.lua")
local Runner = Ext.Require("Shared/DribbleSpec/Runner/Runner.lua")
local Options = Ext.Require("Shared/DribbleSpec/Runner/Options.lua")
local SkipSignal = Ext.Require("Shared/DribbleSpec/Runtime/SkipSignal.lua")
Ext.Require("Shared/DribbleSpec/Tests/Mutation/Fixture.lua")
Ext.Require("Shared/DribbleSpec/Tests/Mutation/LoopFixture.lua")

local RUN_ID = "selftest-agent"
local DIR = "DribbleSpecMutation/" .. RUN_ID .. "/"
local PATCH = DIR .. "1.lua"
local LOOP_PATCH = DIR .. "2.lua"
local FIXTURE_DIR = "Mods/DribbleSpec/ScriptExtender/Lua/Shared/DribbleSpec/Tests/Mutation/"
-- Pinned hash of Fixture.lua; tools/mutation/tests/test_fixture.py checks it and Fixture.patch.txt.
local FIXTURE_HASH = "74478c78"
local LOOP_FIXTURE_HASH = "ed9cbd2f"
local ABOVE = "Fixture IsAtLeast is true above the minimum"
local OTHER = "Fixture other does not call the target"
local SKIPS = "Fixture skips skips when IsAtLeast is wrong"
local HOOK_TEST = "Fixture hook runs after beforeAll"
local HOOK = "Fixture hook [hook] beforeAll"
local LOOP = "Fixture loop approaches the target"
local SWALLOW = "Fixture loop swallows errors from the target"
local FAR = "Fixture loop approaches a far target"
local SKIPPED = "Fixture other is skipped"
-- Mutant ids in LoopFixture.patch.txt: 6 is `<` to `<=` (ends), 7 is `<` to `>=` (never ends).
local LOOP_ENDS, LOOP_FOREVER = 6, 7

---@param sourceHash string
---@param extraFiles table[]|nil plan file entries appended after the fixtures
local function writePlan(sourceHash, extraFiles)
    Ext.IO.SaveFile(PATCH, Ext.IO.LoadFile(FIXTURE_DIR .. "Fixture.patch.txt", "data"))
    Ext.IO.SaveFile(LOOP_PATCH, Ext.IO.LoadFile(FIXTURE_DIR .. "LoopFixture.patch.txt", "data"))
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
        }, {
            index = 2,
            path = "Shared/DribbleSpec/Tests/Mutation/LoopFixture.lua",
            sourceHash = LOOP_FIXTURE_HASH,
            patchPath = LOOP_PATCH,
            targets = { "MutationLoopFixture.Approach" },
        }, table.unpack(extraFiles or {}) },
        mutants = {},
    }))
end

---@param clock (fun(): number)|nil
---@param extra (fun(registry: DribbleSpecRegistry))|nil adds root suites outside the "Fixture " filter
---@return MutationAgent
local function createAgent(clock, extra)
    local registry = Registry.Create()
    registry:BeginSuite("Fixture")
    registry:BeginSuite("IsAtLeast")
    registry:AddTest("is true above the minimum", {}, function()
        Assertions.Equals(MutationFixture.IsAtLeast(5, 1), true, "IsAtLeast(5, 1)")
    end)
    registry:EndSuite()
    registry:BeginSuite("other")
    registry:AddTest("does not call the target", {}, function() end)
    registry:AddTest("is skipped", {}, function() SkipSignal.Throw("always") end)
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
    registry:BeginSuite("loop")
    registry:AddTest("approaches the target", {}, function()
        Assertions.Equals(MutationLoopFixture.Approach(0, 5), 5, "Approach(0, 5)")
    end)
    registry:AddTest("swallows errors from the target", {}, function()
        pcall(MutationLoopFixture.Approach, 0, 5)
    end)
    registry:AddTest("approaches a far target", {}, function()
        Assertions.Equals(MutationLoopFixture.Approach(0, 2000), 2000, "Approach(0, 2000)")
    end)
    registry:EndSuite()
    registry:EndSuite()
    if extra then
        extra(registry)
    end
    return Agent.Create({
        registry = registry,
        clock = clock,
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
            Ext.Json.Stringify({ ABOVE, OTHER, SKIPPED, SKIPS, HOOK_TEST, LOOP, SWALLOW, FAR }, { Beautify = false }), "tests.json")
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

    DribbleSpec.test("DryRun writes a coverage line with no hits for a skipped test", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Equals(agent.DryRun(RUN_ID, { SKIPPED }), "ok", "DryRun")
        local lines = readLines("coverage.jsonl")
        Assertions.Equals(#lines, 1, "coverage lines")
        Assertions.Equals(lines[1].test, SKIPPED, "test")
        Assertions.Equals(lines[1].status, "skipped", "status")
        Assertions.Equals(lines[1].skipReason, "always", "skipReason")
        Assertions.Equals(#lines[1].hits, 0, "hits")
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
        Assertions.Equals(agent.RunMutant(RUN_ID, 1, { ABOVE }, 1), "ok", "RunMutant 1")
        Assertions.Equals(agent.RunMutant(RUN_ID, 2, { ABOVE }, 1), "ok", "RunMutant 2")
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

    DribbleSpec.test("RunMutant classifies an infinite loop as Timeout", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        agent.DryRun(RUN_ID, { LOOP })
        Assertions.Equals(agent.RunMutant(RUN_ID, LOOP_FOREVER, { LOOP }), "ok", "RunMutant")
        local line = readLines("results.jsonl")[1]
        Assertions.Equals(line.status, "Timeout", "status")
        Assertions.Equals(line.message, "step limit", "message")
    end)

    DribbleSpec.test("RunMutant classifies a limit error swallowed by pcall as Timeout", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        agent.RunMutant(RUN_ID, LOOP_FOREVER, { SWALLOW })
        Assertions.Equals(readLines("results.jsonl")[1].status, "Timeout", "status")
    end)

    DribbleSpec.test("RunMutant classifies wall-clock expiry as Timeout", function()
        local now = 0
        agent = createAgent(function()
            now = now + 30000
            return now
        end)
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        -- About 2,000 dry-run steps give a 20,000-step limit, so the 1,000-step clock check fires first.
        agent.DryRun(RUN_ID, { FAR })
        agent.RunMutant(RUN_ID, LOOP_FOREVER, { FAR })
        local line = readLines("results.jsonl")[1]
        Assertions.Equals(line.status, "Timeout", "status")
        Assertions.Equals(line.message, "time limit", "message")
    end)

    DribbleSpec.test("after a Timeout the next mutant starts with a cleared step count and flag", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        agent.RunMutant(RUN_ID, LOOP_FOREVER, { LOOP })
        Assertions.Equals(agent.Runtime.steps, 0, "steps")
        Assertions.Equals(agent.Runtime.limitHit, nil, "limitHit")
        -- Leftovers from gameplay steps or a stale flag must not reach the next mutant.
        agent.Runtime.steps, agent.Runtime.limitHit = 1e6, "steps"
        agent.RunMutant(RUN_ID, LOOP_ENDS, { LOOP })
        Assertions.Equals(readLines("results.jsonl")[2].status, "Survived", "next mutant")
    end)

    DribbleSpec.test("no limit error is raised with no active mutant past the step limit", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        agent.RunMutant(RUN_ID, LOOP_FOREVER, { LOOP })
        local stepLimit = agent.Runtime.stepLimit
        agent.Runtime.stepLimit = 1
        local ok, value = pcall(MutationLoopFixture.Approach, 0, 5)
        agent.Runtime.stepLimit = stepLimit
        Assertions.Equals(ok and value, 5, "Approach(0, 5) with no active mutant")
    end)

    DribbleSpec.test("duplicate full names anywhere in the owner's registry stop Prepare", function()
        agent = createAgent(nil, function(registry)
            registry:BeginSuite("Extra")
            registry:AddTest("twice", {}, function() end)
            registry:AddTest("twice", {}, function() end)
            registry:EndSuite()
        end)
        writePlan(FIXTURE_HASH)
        Assertions.Equals(agent.Prepare(RUN_ID), "error: duplicate test full name: Extra twice", "Prepare")
        Assertions.Equals(MutationFixture.IsAtLeast, original, "not patched")
    end)

    DribbleSpec.test("a chunk error during install restores every target installed before it", function()
        Ext.IO.SaveFile(DIR .. "3.lua", 'error("boom", 0)')
        writePlan(FIXTURE_HASH, { {
            index = 3,
            path = "Shared/DribbleSpec/Tests/Mutation/Fixture.lua",
            sourceHash = FIXTURE_HASH,
            patchPath = DIR .. "3.lua",
            targets = {},
        } })
        local loopOriginal = MutationLoopFixture.Approach
        Assertions.Equals(agent.Prepare(RUN_ID), "error: patch install failed: boom", "Prepare")
        Assertions.Equals(MutationFixture.IsAtLeast, original, "first target restored")
        Assertions.Equals(MutationLoopFixture.Approach, loopOriginal, "second target restored")
    end)

    DribbleSpec.test("a failing baseline test aborts DryRun with its name", function()
        agent = createAgent(nil, function(registry)
            registry:BeginSuite("Extra")
            registry:AddTest("fails", {}, function() error("no", 0) end)
            registry:EndSuite()
        end)
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Equals(agent.DryRun(RUN_ID, { "Extra fails" }), "error: test failed in dry run: Extra fails", "DryRun")
    end)

    DribbleSpec.test("a failing beforeAll aborts DryRun naming the hook and the selected test", function()
        agent = createAgent(nil, function(registry)
            registry:BeginSuite("Extra")
            registry:AddHook("beforeAll", function() error("no", 0) end)
            registry:AddTest("after hook", {}, function() end)
            registry:EndSuite()
        end)
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Assertions.Equals(agent.DryRun(RUN_ID, { "Extra after hook" }),
            "error: test failed in dry run: Extra [hook] beforeAll (selected: Extra after hook)", "DryRun")
    end)

    DribbleSpec.test("Checkpoint runs each set together with no active mutant and lists failing tests", function()
        local dirty = false
        agent = createAgent(nil, function(registry)
            registry:BeginSuite("Extra")
            registry:AddTest("dirties", {}, function() dirty = true end)
            registry:AddTest("needs clean", {}, function()
                Assertions.Equals(dirty, false, "dirty")
            end)
            registry:EndSuite()
        end)
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Ext.IO.SaveFile(DIR .. "checkpoint.jsonl", "")
        Assertions.Equals(agent.Checkpoint(RUN_ID, {
            { set = 4, tests = { ABOVE, "Extra needs clean" } },
            { set = 5, tests = { "Extra dirties", "Extra needs clean" } },
        }), "ok", "Checkpoint")
        local lines = readLines("checkpoint.jsonl")
        Assertions.Equals(#lines, 2, "checkpoint lines")
        Assertions.Equals(lines[1].set, 4, "set")
        Assertions.Equals(lines[1].status, "passed", "clean set")
        Assertions.Equals(#lines[1].failed, 0, "no failures")
        Assertions.Equals(lines[2].status, "failed", "order-dependent set")
        Assertions.Equals(table.concat(lines[2].failed, ","), "Extra needs clean", "failed")
    end)

    DribbleSpec.test("Checkpoint fails a set with a skipped test", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        Ext.IO.SaveFile(DIR .. "checkpoint.jsonl", "")
        Assertions.Equals(agent.Checkpoint(RUN_ID, { { set = 1, tests = { ABOVE, SKIPPED } } }), "ok", "Checkpoint")
        local line = readLines("checkpoint.jsonl")[1]
        Assertions.Equals(line.status, "failed", "status")
        Assertions.Equals(table.concat(line.failed, ","), SKIPPED, "failed")
    end)

    DribbleSpec.test("RunMutant records the attempt it is given", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        agent.RunMutant(RUN_ID, 1, { ABOVE }, 2)
        Assertions.Equals(readLines("results.jsonl")[1].attempt, 2, "attempt")
    end)

    DribbleSpec.test("Prepare rebuilds the dry-run steps from coverage.jsonl", function()
        writePlan(FIXTURE_HASH)
        Ext.IO.SaveFile(DIR .. "coverage.jsonl", Ext.Json.Stringify({ test = LOOP, status = "passed", steps = 300,
            hits = {}, durationMs = 0 }, { Beautify = false }) .. "\n" .. Ext.Json.Stringify({ test = SKIPPED,
            status = "skipped", steps = 900, hits = {}, durationMs = 0 }, { Beautify = false }) .. "\n")
        agent.Prepare(RUN_ID)
        agent.RunMutant(RUN_ID, LOOP_ENDS, { LOOP, SKIPPED }, 1)
        Assertions.Equals(agent.Runtime.stepLimit, 3000, "step limit from the passed line only")
    end)

    DribbleSpec.test("Restore clears an active mutant", function()
        writePlan(FIXTURE_HASH)
        agent.Prepare(RUN_ID)
        agent.Runtime.a = 7
        agent.Restore(RUN_ID)
        Assertions.Equals(agent.Runtime.a, 0, "active mutant")
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
