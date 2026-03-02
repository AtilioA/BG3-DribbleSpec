local Registry = Ext.Require("Lib/DribbleSpec/Core/Registry.lua")
local ResultModel = Ext.Require("Lib/DribbleSpec/Core/ResultModel.lua")
local Runner = Ext.Require("Lib/DribbleSpec/Runner/Runner.lua")
local Options = Ext.Require("Lib/DribbleSpec/Runner/Options.lua")
local Clock = Ext.Require("Lib/DribbleSpec/Internal/Clock.lua")
local Sandbox = Ext.Require("Lib/DribbleSpec/Internal/Sandbox.lua")
local CallerMod = Ext.Require("Lib/DribbleSpec/Internal/CallerMod.lua")
local ManifestLoader = Ext.Require("Lib/DribbleSpec/Internal/ManifestLoader.lua")

---@class DribbleSpecAPI
---@field _VERSION string
---@field _PHASE integer
---@field _internal table
local Dribble = {
    _VERSION = "0.1.0-phase0",
    _PHASE = 0,
}

local registry = Registry.Create()

---@param message string
local function printLine(message)
    if type(Ext) == "table" and type(Ext.Utils) == "table" and type(Ext.Utils.Print) == "function" then
        Ext.Utils.Print(message)
        return
    end

    if type(print) == "function" then
        print(message)
    end
end

---@param message string
local function printWarning(message)
    if type(Ext) == "table" and type(Ext.Utils) == "table" and type(Ext.Utils.PrintWarning) == "function" then
        Ext.Utils.PrintWarning(message)
        return
    end

    printLine(message)
end

local function printHelp()
    printLine("DribbleSpec (Phase 0) usage:")
    printLine("  dribble [--help] [--manifest <path>] [--name <pattern>] [--tag <tag>] [--context <client|server|any>] [--fail-fast] [--mod-uuid <uuid>] [--json-out <path>]")
    printLine("Defaults:")
    printLine("  --manifest DribbleTests.lua")
end

---@param runResult table
local function printSummary(runResult)
    local summary = runResult.summary or {}
    local warningsCount = #(runResult.warnings or {})
    printLine(string.format(
        "[DribbleSpec] status=%s context=%s passed=%d failed=%d skipped=%d total=%d warnings=%d durationMs=%d",
        tostring(runResult.status),
        tostring(runResult.context),
        summary.passed or 0,
        summary.failed or 0,
        summary.skipped or 0,
        summary.total or 0,
        warningsCount,
        runResult.durationMs or 0
    ))
end

---@param options table|nil
---@return table
local function runInternal(options)
    local normalized = Options.Normalize(options or {})
    local loaded, manifestError = ManifestLoader.TryLoad(normalized.manifestPath)
    local runResult = Runner.Run({
        registry = registry,
        options = normalized,
        clock = Clock,
    })

    runResult.manifest = {
        path = normalized.manifestPath,
        loaded = loaded,
        error = manifestError,
    }

    if not loaded then
        ResultModel.AddWarning(runResult,
            string.format("Manifest not loaded from '%s': %s", tostring(normalized.manifestPath), tostring(manifestError)))
    end

    runResult.caller = {
        moduleUUID = normalized.callerModuleUUID,
        name = nil,
    }

    if normalized.callerModuleUUID then
        local callerName, warning = CallerMod.ResolveName(normalized.callerModuleUUID)
        runResult.caller.name = callerName
        if warning then
            ResultModel.AddWarning(runResult, warning)
        end
    end

    return runResult
end

---@param args any[]
---@return table
local function runFromArgs(args)
    local options = Options.ParseArgs(args or {})

    if options.help then
        printHelp()
        return ResultModel.Finalize(ResultModel.NewRun("unknown", options, 0), 0)
    end

    local runResult = runInternal(options)
    printSummary(runResult)
    for _, warning in ipairs(runResult.warnings or {}) do
        printWarning("[DribbleSpec] " .. warning)
    end

    return runResult
end

local function registerCommand()
    if rawget(_G, "__DRIBBLESPEC_COMMAND_REGISTERED") then
        return
    end

    if type(Ext) ~= "table" or type(Ext.RegisterConsoleCommand) ~= "function" then
        return
    end

    Ext.RegisterConsoleCommand("dribble", function(...)
        runFromArgs({ ... })
    end)

    rawset(_G, "__DRIBBLESPEC_COMMAND_REGISTERED", true)
end

local function notAvailable(name)
    error(string.format("DribbleSpec Phase 0: '%s' is not implemented yet.", name), 2)
end

Dribble.Run = runInternal
Dribble.RunFromArgs = runFromArgs
Dribble.ResetRegistry = function()
    registry:Clear()
end
Dribble.GetRegistry = function()
    return registry
end

Dribble.describe = function(...)
    return notAvailable("describe")
end
Dribble.test = function(...)
    return notAvailable("test")
end
Dribble.it = Dribble.test
Dribble.beforeAll = function(...)
    return notAvailable("beforeAll")
end
Dribble.beforeEach = function(...)
    return notAvailable("beforeEach")
end
Dribble.afterEach = function(...)
    return notAvailable("afterEach")
end
Dribble.afterAll = function(...)
    return notAvailable("afterAll")
end

Dribble._internal = {
    registry = registry,
    parseOptions = Options.ParseArgs,
    normalizeOptions = Options.Normalize,
    run = runInternal,
    runFromArgs = runFromArgs,
    sandbox = Sandbox,
    clock = Clock,
    resolveCallerName = CallerMod.ResolveName,
    makeFileSafeName = CallerMod.ToFileSafeName,
}

registerCommand()

return Dribble
