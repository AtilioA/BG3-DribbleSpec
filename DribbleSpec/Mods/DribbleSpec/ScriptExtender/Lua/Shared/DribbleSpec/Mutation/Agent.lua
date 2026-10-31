-- Mutation agent (`Mods.Dribbles.Mutation`): installs host patch chunks and runs tests per mutant.
-- Each call returns "ok" or "error: <message>" and writes its data under `DribbleSpecMutation/<runId>/`.
local Runtime = Ext.Require("Shared/DribbleSpec/Mutation/Runtime.lua")
local Filter = Ext.Require("Shared/DribbleSpec/Runner/Filter.lua")

---@class MutationAgentDeps
---@field registry DribbleSpecRegistry tests to resolve the plan's testFilter against
---@field run fun(options: table): table runs tests and returns a DribbleSpec run result
---@field clock (fun(): number)|nil milliseconds; defaults to Ext.Timer.MonotonicTime

---@class MutationAgent
---@field Runtime MutationRuntime
local Agent = {}

local MIN_STEP_LIMIT = 1000
local STEP_LIMIT_FACTOR = 10
local WALL_CLOCK_MS = 20000
local LIMIT_MESSAGES = { steps = "step limit", time = "time limit" }

---@param data string
---@return string
local function fnv1a32(data)
    local h = 2166136261
    data = data:gsub("\r\n", "\n")
    for i = 1, #data do
        h = ((h ~ data:byte(i)) * 16777619) & 0xFFFFFFFF
    end
    return string.format("%08x", h)
end

---@param runId string
---@param name string
---@return string
local function runPath(runId, name)
    return string.format("DribbleSpecMutation/%s/%s", runId, name)
end

---@param path string
---@param value table
local function appendLine(path, value)
    if not Ext.IO.AppendFile(path, Ext.Json.Stringify(value, { Beautify = false }) .. "\n") then
        error("cannot write " .. path, 0)
    end
end

---@param runId string
---@return table
local function loadPlan(runId)
    local text = Ext.IO.LoadFile(runPath(runId, "plan.json"))
    if text == nil then
        error("cannot read " .. runPath(runId, "plan.json"), 0)
    end
    return Ext.Json.Parse(text)
end

---@param env table
---@param target string dotted path such as "A.B"
---@return table parent, string key
local function resolveTarget(env, target)
    local parent = env
    local keys = {}
    for key in target:gmatch("[^.]+") do
        table.insert(keys, key)
    end
    for i = 1, #keys - 1 do
        parent = parent[keys[i]]
        if type(parent) ~= "table" then
            error(string.format("target %s: %s is not a table", target, keys[i]), 0)
        end
    end
    local key = keys[#keys]
    if type(parent[key]) ~= "function" then
        error(string.format("target %s is not a function", target), 0)
    end
    return parent, key
end

--- Duplicates are checked over every test of the owner, since `testIds` can select any of them.
---@param registry DribbleSpecRegistry
---@param testFilter table|nil
---@param owner string
---@return string[]
local function resolveTests(registry, testFilter, owner)
    testFilter = testFilter or {}
    local filter = Filter.Create({
        tags = testFilter.tags,
        namePattern = testFilter.name,
        ownerModuleUUID = owner,
    })
    local owned = Filter.Create({ ownerModuleUUID = owner })
    local ids, seen = {}, {}
    local function walk(suite, lineage)
        table.insert(lineage, suite)
        for _, test in ipairs(suite.tests) do
            if owned.ShouldIncludeTest(lineage, test) then
                if seen[test.fullName] then
                    error("duplicate test full name: " .. test.fullName, 0)
                end
                seen[test.fullName] = true
            end
            if filter.ShouldIncludeTest(lineage, test) then
                table.insert(ids, test.fullName)
            end
        end
        for _, child in ipairs(suite.suites) do
            walk(child, lineage)
        end
        table.remove(lineage)
    end
    for _, suite in ipairs(registry:Snapshot().suites) do
        walk(suite, {})
    end
    return ids
end

---@param suites table[]
---@param visit fun(test: table)
local function eachResult(suites, visit)
    for _, suite in ipairs(suites or {}) do
        for _, test in ipairs(suite.tests or {}) do
            visit(test)
        end
        eachResult(suite.suites, visit)
    end
end

---@param fn function
---@return string
local function guarded(fn)
    local ok, err = xpcall(fn, function(e)
        return tostring(e)
    end)
    if ok then
        return "ok"
    end
    -- The console transport breaks on non-ASCII result bytes.
    return "error: " .. err:gsub("[\128-\255]", function(c) return "\\" .. c:byte() end)
end

---@param deps MutationAgentDeps
---@return MutationAgent
function Agent.Create(deps)
    local agent = { Runtime = Runtime }
    ---@type { parent: table, key: string, fn: function }[]|nil
    local originals = nil
    ---@type string|nil ModuleUUID of the prepared plan's mod; nil when no run is prepared
    local owner = nil
    local clock = deps.clock or Ext.Timer.MonotonicTime
    ---@type table<string, integer> steps per passed test in this agent's dry runs
    local dryRunSteps = {}

    local function runOptions(testIds)
        return { ownerModuleUUID = owner, testIds = testIds }
    end

    local function restore()
        Runtime.a = 0
        for i = #(originals or {}), 1, -1 do
            local o = originals[i]
            o.parent[o.key] = o.fn
        end
        originals = nil
    end

    --- After a reset the agent is fresh, so the steps come from the run's earlier dry runs.
    ---@param runId string
    local function loadDryRunSteps(runId)
        dryRunSteps = {}
        for line in (Ext.IO.LoadFile(runPath(runId, "coverage.jsonl")) or ""):gmatch("[^\n]+") do
            local ok, c = pcall(Ext.Json.Parse, line)
            if ok then
                dryRunSteps[c.test] = c.status == "passed" and c.steps or nil
            end
        end
    end

    ---@param runId string
    ---@return string
    function agent.Prepare(runId)
        return guarded(function()
            if originals ~= nil then
                error("patches are active; call Restore first", 0)
            end
            local p = loadPlan(runId)
            local env = Mods[p.modTable]
            if type(env) ~= "table" then
                error("mod table not loaded: " .. tostring(p.modTable), 0)
            end
            local modOwner = env.ModuleUUID
            local directory = Ext.Mod.GetMod(modOwner).Info.Directory
            local chunks, targets = {}, {}
            for _, file in ipairs(p.files) do
                local sourcePath = string.format("Mods/%s/ScriptExtender/Lua/%s", directory, file.path)
                local source = Ext.IO.LoadFile(sourcePath, "data")
                if source == nil then
                    error("cannot read deployed source " .. sourcePath, 0)
                end
                if fnv1a32(source) ~= file.sourceHash then
                    error("deployed source differs from repo: " .. file.path, 0)
                end
                local patchPath = runPath(runId, file.index .. ".lua")
                local text = Ext.IO.LoadFile(patchPath)
                if text == nil then
                    error("cannot read patch " .. patchPath, 0)
                end
                local chunk, compileError = load(text, env)
                if chunk == nil then
                    error(string.format("patch %s does not compile: %s", patchPath, tostring(compileError)), 0)
                end
                table.insert(chunks, chunk)
                for _, target in ipairs(file.targets) do
                    local parent, key = resolveTarget(env, target)
                    table.insert(targets, { parent = parent, key = key, fn = parent[key] })
                end
            end
            local testIds = resolveTests(deps.registry, p.testFilter, modOwner)
            if not Ext.IO.SaveFile(runPath(runId, "tests.json"), Ext.Json.Stringify(testIds, { Beautify = false })) then
                error("cannot write " .. runPath(runId, "tests.json"), 0)
            end

            originals = targets
            for _, chunk in ipairs(chunks) do
                local ok, err = pcall(chunk)
                if not ok then
                    restore()
                    error("patch install failed: " .. tostring(err), 0)
                end
            end
            loadDryRunSteps(runId)
            owner = modOwner
        end)
    end

    ---@param runId string
    ---@param testIds string[]
    ---@return string
    function agent.DryRun(runId, testIds)
        return guarded(function()
            if owner == nil then
                error("no prepared run; call Prepare first", 0)
            end
            local ok, err = xpcall(function()
                Runtime.a = 0
                for _, id in ipairs(testIds) do
                    Runtime.hits, Runtime.steps = {}, 0
                    local started = clock()
                    local run = deps.run(runOptions({ id }))
                    local result, failed
                    eachResult(run.suites, function(test)
                        if test.fullName == id then result = test end
                        if test.status == "failed" then failed = failed or test.fullName end
                    end)
                    if failed ~= nil then
                        error("test failed in dry run: " .. failed .. (failed ~= id and " (selected: " .. id .. ")" or ""), 0)
                    end
                    if result == nil then
                        error("test not run: " .. id, 0)
                    end
                    local status = result.status
                    -- Skipped tests also get a line, so the host can see every id of a batch finish.
                    local hits = {}
                    if status == "passed" then
                        dryRunSteps[id] = Runtime.steps
                        for hit in pairs(Runtime.hits) do
                            table.insert(hits, hit)
                        end
                        table.sort(hits)
                    end
                    appendLine(runPath(runId, "coverage.jsonl"), {
                        test = id,
                        status = status,
                        durationMs = clock() - started,
                        steps = Runtime.steps,
                        hits = hits,
                        skipReason = status == "skipped" and (result.skipReason or "skipped") or nil,
                    })
                end
            end, function(e) return tostring(e) end)
            Runtime.hits, Runtime.steps = nil, 0
            if not ok then
                error(err, 0)
            end
        end)
    end

    --- Runs each set as one run with no active mutant; a set fails when any of its tests does not pass.
    ---@param runId string
    ---@param sets { set: integer, tests: string[] }[]
    ---@return string
    function agent.Checkpoint(runId, sets)
        return guarded(function()
            if owner == nil then
                error("no prepared run; call Prepare first", 0)
            end
            Runtime.a = 0
            for _, set in ipairs(sets) do
                local started = clock()
                local run = deps.run(runOptions(set.tests))
                local failed, passed = {}, 0
                eachResult(run.suites, function(test)
                    if test.status == "passed" then
                        passed = passed + 1
                    else
                        table.insert(failed, test.fullName)
                    end
                end)
                appendLine(runPath(runId, "checkpoint.jsonl"), {
                    set = set.set,
                    status = (#failed == 0 and passed == #set.tests) and "passed" or "failed",
                    failed = failed,
                    durationMs = clock() - started,
                })
            end
        end)
    end

    ---@param runId string
    ---@param mutantId integer
    ---@param testIds string[]
    ---@param attempt integer 2 when the host re-runs the mutant after a recovery
    ---@return string
    function agent.RunMutant(runId, mutantId, testIds, attempt)
        return guarded(function()
            if owner == nil then
                error("no prepared run; call Prepare first", 0)
            end
            local result = { mutantId = mutantId, killedBy = {}, passed = 0, failed = 0, skipped = 0, attempt = attempt }
            local covered = 0
            for _, id in ipairs(testIds) do
                covered = covered + (dryRunSteps[id] or 0)
            end
            local started = clock()
            Runtime.steps, Runtime.limitHit, Runtime.hits = 0, nil, nil
            Runtime.stepLimit = math.max(MIN_STEP_LIMIT, STEP_LIMIT_FACTOR * covered)
            Runtime.clock, Runtime.deadlineMs = clock, started + WALL_CLOCK_MS
            Runtime.a = mutantId
            local ok, run = xpcall(deps.run, function(e) return tostring(e) end, runOptions(testIds))
            Runtime.a = 0
            local limitHit = Runtime.limitHit
            Runtime.steps, Runtime.limitHit = 0, nil
            result.durationMs = clock() - started

            if limitHit ~= nil then
                result.status, result.message = "Timeout", LIMIT_MESSAGES[limitHit]
                eachResult(ok and run.suites or nil, function(test)
                    result[test.status] = (result[test.status] or 0) + 1
                end)
            elseif not ok then
                result.status, result.message = "RuntimeError", run:match("[^\n]*")
            else
                eachResult(run.suites, function(test)
                    result[test.status] = (result[test.status] or 0) + 1
                    if test.status == "failed" then
                        table.insert(result.killedBy, test.fullName)
                        if result.message == nil and test.error ~= nil then
                            result.message = tostring(test.error.message):match("[^\n]*")
                        end
                    end
                end)
                if result.failed > 0 then
                    result.status = "Killed"
                elseif result.passed == #testIds and result.skipped == 0 then
                    result.status = "Survived"
                else
                    result.status = "RuntimeError"
                    result.message = string.format("%d of %d tests passed, %d skipped", result.passed, #testIds,
                        result.skipped)
                end
            end
            appendLine(runPath(runId, "results.jsonl"), result)
        end)
    end

    ---@param _runId string
    ---@return string
    function agent.Restore(_runId)
        return guarded(function()
            restore()
            owner = nil
        end)
    end

    return agent
end

return Agent
