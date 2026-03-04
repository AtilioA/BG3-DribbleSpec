local ResultModel = Ext.Require("Shared/DribbleSpec/Core/ResultModel.lua")
local Sandbox = Ext.Require("Shared/DribbleSpec/Internal/Sandbox.lua")
local Filter = Ext.Require("Shared/DribbleSpec/Runner/Filter.lua")
local Expect = Ext.Require("Shared/DribbleSpec/Expect/Expect.lua")
local Doubles = Ext.Require("Shared/DribbleSpec/Doubles/Doubles.lua")
local RuntimeHelpers = Ext.Require("Shared/DribbleSpec/Runtime/Helpers.lua")
local SkipSignal = Ext.Require("Shared/DribbleSpec/Runtime/SkipSignal.lua")
local FixtureManager = Ext.Require("Shared/DribbleSpec/Fixtures/Manager.lua")
local EntityRef = Ext.Require("Shared/DribbleSpec/Entity/EntityRef.lua")

local Runner = {}

---@param message string
---@param stack string|nil
---@return table
local function createErrorRecord(message, stack)
    return {
        message = tostring(message or "Unknown error"),
        stack = stack,
    }
end

---@param suite table
---@param test table
---@param runContext string
---@param options table
---@return table
local function createContext(suite, test, runContext, options)
    local sandbox = Sandbox.Create()
    local runtimeHelpers = RuntimeHelpers.Create({
        context = runContext,
        options = options,
    })
    local fixtureManager = FixtureManager.Create({
        sandbox = sandbox,
        context = runContext,
        options = options,
        suite = suite,
        test = test,
    })

    return {
        meta = {
            suiteName = suite and suite.fullName or nil,
            testName = test and test.name or nil,
            fullName = test and test.fullName or (suite and suite.fullName or nil),
        },
        sandbox = sandbox,
        expect = Expect.Expect,
        mockFn = function(impl)
            return Doubles.CreateMockFn(impl)
        end,
        spyOn = function(target, methodName)
            return Doubles.CreateSpyOn(sandbox, target, methodName)
        end,
        stub = function(target, methodName, impl)
            return Doubles.CreateStub(sandbox, target, methodName, impl)
        end,
        requireClient = runtimeHelpers.requireClient,
        requireServer = runtimeHelpers.requireServer,
        nextTick = runtimeHelpers.nextTick,
        waitUntil = runtimeHelpers.waitUntil,
        fixture = fixtureManager:BuildApi(),
        entityRef = function(source)
            return EntityRef.Create(source)
        end,
    }
end

---@param err any
---@return any
local function tracebackOrSkip(err)
    if SkipSignal.Is(err) then
        return err
    end

    return debug.traceback(tostring(err), 2)
end

---@param run table
---@param suiteResult table
---@param testResult table
local function pushTestResult(run, suiteResult, testResult)
    table.insert(suiteResult.tests, testResult)

    if testResult.status == "passed" then
        run.summary.passed = run.summary.passed + 1
    elseif testResult.status == "failed" then
        run.summary.failed = run.summary.failed + 1
    else
        run.summary.skipped = run.summary.skipped + 1
    end
end

---@param nowMs function
---@param test table
---@param status "passed"|"failed"|"skipped"
---@param errorRecord table|nil
---@param skipReason string|nil
---@return table
local function newTestResult(nowMs, test, status, errorRecord, skipReason)
    local started = nowMs()
    local finished = nowMs()
    return {
        name = test and test.name or "[hook]",
        fullName = test and test.fullName or "[hook]",
        status = status,
        tags = (test and test.metadata and test.metadata.tags) or {},
        startedAtMs = started,
        finishedAtMs = finished,
        durationMs = math.max(0, finished - started),
        error = errorRecord,
        skipReason = skipReason,
    }
end

---@param hook table
---@param context table
---@return boolean, table|nil
local function runHook(hook, context)
    local ok, err = xpcall(function()
        hook.callback(context)
    end, tracebackOrSkip)

    if ok then
        return true, nil
    end

    if SkipSignal.Is(err) then
        return false, {
            skipReason = SkipSignal.Reason(err),
            skipped = true,
        }
    end

    return false, createErrorRecord(err, err)
end

---@param hooks table[]
---@param context table
---@return boolean, table|nil
local function runHooks(hooks, context)
    for _, hook in ipairs(hooks or {}) do
        local ok, err = runHook(hook, context)
        if not ok then
            return false, err
        end
    end

    return true, nil
end

---@param lineage table[]
---@return table[]
local function collectBeforeEachHooks(lineage)
    local hooks = {}
    for _, suite in ipairs(lineage) do
        for _, hook in ipairs(suite.hooks.beforeEach) do
            table.insert(hooks, hook)
        end
    end
    return hooks
end

---@param lineage table[]
---@return table[]
local function collectAfterEachHooks(lineage)
    local hooks = {}
    for i = #lineage, 1, -1 do
        local suite = lineage[i]
        for _, hook in ipairs(suite.hooks.afterEach) do
            table.insert(hooks, hook)
        end
    end
    return hooks
end

---@param suite table
---@return boolean
local function suiteHasOnly(suite)
    if suite.only == true then
        return true
    end

    for _, test in ipairs(suite.tests or {}) do
        if test.only == true then
            return true
        end
    end

    for _, child in ipairs(suite.suites or {}) do
        if suiteHasOnly(child) then
            return true
        end
    end

    return false
end

---@param suite table
---@param nowMs function
---@return table
local function newSuiteResult(suite, nowMs)
    return {
        name = suite.fullName or suite.name,
        tags = (suite.metadata and suite.metadata.tags) or {},
        startedAtMs = nowMs(),
        finishedAtMs = 0,
        durationMs = 0,
        tests = {},
        suites = {},
    }
end

---@return string
function Runner.DetectContext()
    if Ext.IsClient() then
        return "client"
    end

    if Ext.IsServer() then
        return "server"
    end

    return "unknown"
end

---@param params table
---@return table
function Runner.Run(params)
    local registry = params.registry
    local options = params.options or {}
    local clock = params.clock
    local nowMs = (clock and clock.NowMs) and clock.NowMs or function() return 0 end
    local filter = Filter.Create(options)

    local run = ResultModel.NewRun(Runner.DetectContext(), options, nowMs())

    local snapshot = { suites = {} }
    if registry and type(registry.Snapshot) == "function" then
        snapshot = registry:Snapshot()
    end

    local hasOnly = snapshot.hasOnly == true
    local stopRequested = false

    ---@param suite table
    ---@param lineage table[]
    ---@return boolean
    local function suiteHasSelectedTests(suite, lineage)
        local currentLineage = {}
        for i = 1, #lineage do
            currentLineage[i] = lineage[i]
        end
        table.insert(currentLineage, suite)

        for _, test in ipairs(suite.tests or {}) do
            if filter.ShouldIncludeTest(currentLineage, test) then
                return true
            end
        end

        for _, childSuite in ipairs(suite.suites or {}) do
            if suiteHasSelectedTests(childSuite, currentLineage) then
                return true
            end
        end

        return false
    end

    ---@param suite table
    ---@param lineage table[]
    ---@param parentSuiteResult table|nil
    ---@param inheritedSkipReason string|nil
    local function executeSuite(suite, lineage, parentSuiteResult, inheritedSkipReason)
        if stopRequested then
            return
        end

        if not suiteHasSelectedTests(suite, lineage) then
            return
        end

        local suiteResult = newSuiteResult(suite, nowMs)
        if parentSuiteResult then
            table.insert(parentSuiteResult.suites, suiteResult)
        else
            table.insert(run.suites, suiteResult)
        end

        local currentLineage = {}
        for i = 1, #lineage do
            currentLineage[i] = lineage[i]
        end
        table.insert(currentLineage, suite)

        local focusedSkipReason = nil
        if hasOnly and not suiteHasOnly(suite) and suite.only ~= true then
            focusedSkipReason = "Excluded by test.only focus"
        end

        local suiteSkipReason = inheritedSkipReason
        if not suiteSkipReason and suite.skip == true then
            suiteSkipReason = "Suite marked skip"
        end
        if not suiteSkipReason and focusedSkipReason then
            suiteSkipReason = focusedSkipReason
        end

        local setupFailureSkipReason = nil
        if not suiteSkipReason then
            local suiteContext = createContext(suite, nil, run.context, options)
            local okBeforeAll, beforeAllError = runHooks(suite.hooks.beforeAll, suiteContext)
            suiteContext.sandbox:RestoreAll()
            if not okBeforeAll then
                if type(beforeAllError) == "table" and beforeAllError.skipped == true then
                    setupFailureSkipReason = beforeAllError.skipReason or "Skipped by runtime helper"
                else
                    local hookResult = newTestResult(nowMs, {
                        name = "[hook] beforeAll",
                        fullName = string.format("%s [hook] beforeAll", suite.fullName or suite.name),
                        metadata = {},
                    }, "failed", beforeAllError, nil)
                    pushTestResult(run, suiteResult, hookResult)
                    setupFailureSkipReason = "Suite beforeAll failed"
                    if options.failFast == true then
                        stopRequested = true
                    end
                end
            end
        end

        local effectiveSkipReason = suiteSkipReason or setupFailureSkipReason

        for _, test in ipairs(suite.tests or {}) do
            if stopRequested then
                break
            end

            if filter.ShouldIncludeTest(currentLineage, test) then
                local testSkipReason = effectiveSkipReason
                if not testSkipReason and test.skip == true then
                    testSkipReason = "Test marked skip"
                end
                if not testSkipReason and hasOnly and test.only ~= true and suite.only ~= true then
                    testSkipReason = "Excluded by test.only focus"
                end

                if testSkipReason then
                    local skippedResult = newTestResult(nowMs, test, "skipped", nil, testSkipReason)
                    pushTestResult(run, suiteResult, skippedResult)
                else
                    local testStart = nowMs()
                    local testContext = createContext(suite, test, run.context, options)
                    local testStatus = "passed"
                    local testError = nil
                    local testSkipReason = nil

                    local okBeforeEach, beforeEachError = runHooks(collectBeforeEachHooks(currentLineage), testContext)
                    if not okBeforeEach then
                        if type(beforeEachError) == "table" and beforeEachError.skipped == true then
                            testStatus = "skipped"
                            testSkipReason = beforeEachError.skipReason or "Skipped by runtime helper"
                        else
                            testStatus = "failed"
                            testError = beforeEachError
                        end
                    end

                    if testStatus == "passed" then
                        local okTest, testErr = xpcall(function()
                            test.callback(testContext)
                        end, tracebackOrSkip)
                        if not okTest then
                            if SkipSignal.Is(testErr) then
                                testStatus = "skipped"
                                testSkipReason = SkipSignal.Reason(testErr)
                            else
                                testStatus = "failed"
                                testError = createErrorRecord(testErr, testErr)
                            end
                        end
                    end

                    local okAfterEach, afterEachError = runHooks(collectAfterEachHooks(currentLineage), testContext)
                    if not okAfterEach and testStatus == "passed" then
                        if type(afterEachError) == "table" and afterEachError.skipped == true then
                            testStatus = "skipped"
                            testSkipReason = afterEachError.skipReason or "Skipped by runtime helper"
                        else
                            testStatus = "failed"
                            testError = afterEachError
                        end
                    end

                    testContext.sandbox:RestoreAll()

                    local testFinish = nowMs()
                    local result = {
                        name = test.name,
                        fullName = test.fullName,
                        status = testStatus,
                        tags = (test.metadata and test.metadata.tags) or {},
                        startedAtMs = testStart,
                        finishedAtMs = testFinish,
                        durationMs = math.max(0, testFinish - testStart),
                        error = testError,
                        skipReason = testSkipReason,
                    }
                    pushTestResult(run, suiteResult, result)

                    if testStatus == "failed" and options.failFast == true then
                        stopRequested = true
                    end
                end
            end
        end

        for _, childSuite in ipairs(suite.suites or {}) do
            executeSuite(childSuite, currentLineage, suiteResult, effectiveSkipReason)
            if stopRequested then
                break
            end
        end

        if not stopRequested and not suiteSkipReason then
            local suiteContext = createContext(suite, nil, run.context, options)
            local okAfterAll, afterAllError = runHooks(suite.hooks.afterAll, suiteContext)
            suiteContext.sandbox:RestoreAll()
            if not okAfterAll then
                if type(afterAllError) ~= "table" or afterAllError.skipped ~= true then
                    local hookResult = newTestResult(nowMs, {
                        name = "[hook] afterAll",
                        fullName = string.format("%s [hook] afterAll", suite.fullName or suite.name),
                        metadata = {},
                    }, "failed", afterAllError, nil)
                    pushTestResult(run, suiteResult, hookResult)
                    if options.failFast == true then
                        stopRequested = true
                    end
                end
            end
        end

        suiteResult.finishedAtMs = nowMs()
        suiteResult.durationMs = math.max(0, suiteResult.finishedAtMs - suiteResult.startedAtMs)
    end

    for _, suite in ipairs(snapshot.suites or {}) do
        executeSuite(suite, {}, nil, nil)
        if stopRequested then
            break
        end
    end

    return ResultModel.Finalize(run, nowMs())
end

return Runner
