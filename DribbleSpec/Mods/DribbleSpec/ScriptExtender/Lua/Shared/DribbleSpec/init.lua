local Registry = Ext.Require("Shared/DribbleSpec/Core/Registry.lua")
local ResultModel = Ext.Require("Shared/DribbleSpec/Core/ResultModel.lua")
local Runner = Ext.Require("Shared/DribbleSpec/Runner/Runner.lua")
local Options = Ext.Require("Shared/DribbleSpec/Runner/Options.lua")
local Clock = Ext.Require("Shared/DribbleSpec/Internal/Clock.lua")
local Sandbox = Ext.Require("Shared/DribbleSpec/Internal/Sandbox.lua")
local CallerMod = Ext.Require("Shared/DribbleSpec/Internal/CallerMod.lua")
local ManifestLoader = Ext.Require("Shared/DribbleSpec/Internal/ManifestLoader.lua")
local ConsoleReporter = Ext.Require("Shared/DribbleSpec/Reporters/ConsoleReporter.lua")
local ExecutionRouter = Ext.Require("Shared/DribbleSpec/Runtime/ExecutionRouter.lua")

---@class DribbleSpecAPI
---@field _VERSION string
---@field _PHASE integer
---@field _internal table
local Dribble = {
    _VERSION = "0.2.0-phase1",
    _PHASE = 1,
}

_G.Dribble = Dribble

local registry = Registry.Create()
local loadedManifests = {}
local serverRunChannel = nil

local SERVER_RUN_CHANNEL_NAME = "DribbleSpec_RunServer"

---@return table|nil
local function getServerRunChannel()
    if serverRunChannel then
        return serverRunChannel
    end

    if type(Ext) ~= "table" or type(Ext.Net) ~= "table" or type(Ext.Net.CreateChannel) ~= "function" then
        return nil
    end

    serverRunChannel = Ext.Net.CreateChannel(ModuleUUID, SERVER_RUN_CHANNEL_NAME)
    return serverRunChannel
end

---@param manifestPath string
---@param forceReload boolean|nil
---@return boolean loaded
---@return string|nil errorMessage
---@return boolean attempted
local function loadManifest(manifestPath, forceReload)
    if forceReload ~= true and loadedManifests[manifestPath] == true then
        return true, nil, false
    end

    local loaded, err = ManifestLoader.TryLoad(manifestPath)
    if loaded then
        loadedManifests[manifestPath] = true
    end

    return loaded, err, true
end

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
    printLine("DribbleSpec (Phase 1) usage:")
    printLine("  dribble [--help] [--manifest <path>] [--name <pattern>] [--tag <tag>] [--context <client|server|any>] [--fail-fast] [--mod-uuid <uuid>] [--json-out <path>]")
    printLine("Defaults:")
    printLine("  --manifest DribbleTests.lua")
end

---@param options table|nil
---@return table
local function runInternal(options)
    local normalized = Options.Normalize(options or {})
    local loaded, manifestError, manifestAttempted = loadManifest(normalized.manifestPath, normalized.reloadManifest == true)
    local runResult = Runner.Run({
        registry = registry,
        options = normalized,
        clock = Clock,
    })

    runResult.manifest = {
        path = normalized.manifestPath,
        attempted = manifestAttempted,
        loaded = loaded,
        error = manifestError,
    }

    if manifestAttempted and not loaded then
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

    local runResult = ExecutionRouter.Run(options, {
        isClient = function()
            return type(Ext) == "table" and type(Ext.IsClient) == "function" and Ext.IsClient() == true
        end,
        requestServerRun = function(remoteOptions, onReply)
            local channel = getServerRunChannel()
            if not channel or type(channel.RequestToServer) ~= "function" then
                printWarning("[DribbleSpec] Server run channel unavailable on client.")
                onReply(nil)
                return
            end

            channel:RequestToServer({
                options = remoteOptions,
            }, function(response)
                onReply(response)
            end)
        end,
        runLocal = runInternal,
        renderRun = function(run)
            ConsoleReporter.PrintRun(run, {
                printLine = printLine,
                printWarning = printWarning,
            })
        end,
        buildPendingRun = function(pendingOptions)
            local pending = ResultModel.NewRun("client", pendingOptions, 0)
            ResultModel.AddWarning(pending,
                "Server-context run requested from client; final result will print asynchronously.")
            return ResultModel.Finalize(pending, 0)
        end,
        printLine = printLine,
        printWarning = printWarning,
    })

    return runResult
end

local function registerServerRunHandler()
    if rawget(_G, "__DRIBBLESPEC_SERVER_RUN_HANDLER_REGISTERED") then
        return
    end

    if type(Ext) ~= "table" or type(Ext.IsServer) ~= "function" or Ext.IsServer() ~= true then
        return
    end

    local channel = getServerRunChannel()
    if not channel or type(channel.SetRequestHandler) ~= "function" then
        return
    end

    channel:SetRequestHandler(function(data, _)
        local payload = type(data) == "table" and data or {}
        local remoteOptions = Options.Normalize(payload.options or {})
        remoteOptions.context = "server"

        local runResult = runInternal(remoteOptions)
        return {
            runResult = runResult,
        }
    end)

    rawset(_G, "__DRIBBLESPEC_SERVER_RUN_HANDLER_REGISTERED", true)
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
    error(string.format("DribbleSpec Phase 1: '%s' is not implemented yet.", name), 2)
end

---@param optionsOrCallback table|function|nil
---@param maybeCallback function|nil
---@param callsite string
---@return table, function
local function resolveMetadataAndCallback(optionsOrCallback, maybeCallback, callsite)
    if type(optionsOrCallback) == "function" and maybeCallback == nil then
        return {}, optionsOrCallback
    end

    if type(optionsOrCallback) == "table" and type(maybeCallback) == "function" then
        return optionsOrCallback, maybeCallback
    end

    error(string.format("%s() expects (%s, callback) or (%s, options, callback)", callsite, "name", "name"), 3)
end

---@param name string
---@param optionsOrCallback table|function|nil
---@param maybeCallback function|nil
---@param metadataPatch table|nil
---@return table
local function registerTest(name, optionsOrCallback, maybeCallback, metadataPatch)
    local metadata, callback = resolveMetadataAndCallback(optionsOrCallback, maybeCallback, "test")
    if metadataPatch then
        for k, v in pairs(metadataPatch) do
            metadata[k] = v
        end
    end

    return registry:AddTest(name, metadata, callback)
end

Dribble.Run = runInternal
Dribble.RunFromArgs = runFromArgs
Dribble.ResetRegistry = function()
    registry:Clear()
end
Dribble.GetRegistry = function()
    return registry
end

---@param name string
---@param optionsOrCallback table|function
---@param maybeCallback function|nil
function Dribble.describe(name, optionsOrCallback, maybeCallback)
    local metadata, callback = resolveMetadataAndCallback(optionsOrCallback, maybeCallback, "describe")
    registry:BeginSuite(name, metadata)

    local ok, err = xpcall(function()
        callback()
    end, debug.traceback)

    registry:EndSuite()
    if not ok then
        error(err, 0)
    end
end

---@param name string
---@param optionsOrCallback table|function
---@param maybeCallback function|nil
local function testMain(name, optionsOrCallback, maybeCallback)
    return registerTest(name, optionsOrCallback, maybeCallback, nil)
end

---@param name string
---@param optionsOrCallback table|function
---@param maybeCallback function|nil
local function testSkip(name, optionsOrCallback, maybeCallback)
    return registerTest(name, optionsOrCallback, maybeCallback, { skip = true })
end

---@param name string
---@param optionsOrCallback table|function
---@param maybeCallback function|nil
local function testOnly(name, optionsOrCallback, maybeCallback)
    return registerTest(name, optionsOrCallback, maybeCallback, { only = true })
end

Dribble.test = setmetatable({
    skip = testSkip,
    only = testOnly,
}, {
    __call = function(_, name, optionsOrCallback, maybeCallback)
        return testMain(name, optionsOrCallback, maybeCallback)
    end,
})

Dribble.it = Dribble.test

---@param callback function
function Dribble.beforeAll(callback)
    return registry:AddHook("beforeAll", callback)
end

---@param callback function
function Dribble.beforeEach(callback)
    return registry:AddHook("beforeEach", callback)
end

---@param callback function
function Dribble.afterEach(callback)
    return registry:AddHook("afterEach", callback)
end

---@param callback function
function Dribble.afterAll(callback)
    return registry:AddHook("afterAll", callback)
end

Dribble._internal = {
    registry = registry,
    notAvailable = notAvailable,
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
registerServerRunHandler()

local bootstrapLoaded, bootstrapError = loadManifest(Options.DEFAULT_MANIFEST_PATH, false)
if not bootstrapLoaded then
    printWarning(string.format("[DribbleSpec] Bootstrap manifest load failed for '%s': %s",
        tostring(Options.DEFAULT_MANIFEST_PATH), tostring(bootstrapError)))
end

return Dribble
