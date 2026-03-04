local Registry = Ext.Require("Shared/DribbleSpec/Core/Registry.lua")
local ApiBinder = Ext.Require("Shared/DribbleSpec/Core/ApiBinder.lua")
local PublicSymbols = Ext.Require("Shared/DribbleSpec/Core/PublicSymbols.lua")
local ResultModel = Ext.Require("Shared/DribbleSpec/Core/ResultModel.lua")
local Runner = Ext.Require("Shared/DribbleSpec/Runner/Runner.lua")
local Options = Ext.Require("Shared/DribbleSpec/Runner/Options.lua")
local Clock = Ext.Require("Shared/DribbleSpec/Internal/Clock.lua")
local Sandbox = Ext.Require("Shared/DribbleSpec/Internal/Sandbox.lua")
local ConsoleIO = Ext.Require("Shared/DribbleSpec/Internal/ConsoleIO.lua")
local ConsoleReporter = Ext.Require("Shared/DribbleSpec/Reporters/ConsoleReporter.lua")
local ExecutionRouter = Ext.Require("Shared/DribbleSpec/Runtime/ExecutionRouter.lua")
local RunService = Ext.Require("Shared/DribbleSpec/Runtime/RunService.lua")
local ServerRunChannel = Ext.Require("Shared/DribbleSpec/Runtime/ServerRunChannel.lua")
local Expect = Ext.Require("Shared/DribbleSpec/Expect/Expect.lua")
local EntityRef = Ext.Require("Shared/DribbleSpec/Entity/EntityRef.lua")
local SkipSignal = Ext.Require("Shared/DribbleSpec/Runtime/SkipSignal.lua")

---@class DribbleSpecAPI
---@field _VERSION string
---@field _PHASE integer
---@field _internal table
local DribbleSpec = {
    _VERSION = "0.8.0-phase8",
    _PHASE = 8,
}

local CONSUMER_ALIAS_REGISTRY_KEY = "__DRIBBLESPEC_CONSUMER_COMMAND_ALIASES"
local RESERVED_COMMAND_NAMES = {
    dribbles = true,
    d = true,
}

_G.DribbleSpec = DribbleSpec

local registry = Registry.Create()
local runService = RunService.Create({
    registry = registry,
    options = Options,
    clock = Clock,
    runner = Runner,
    resultModel = ResultModel,
})

local serverRunChannel = ServerRunChannel.Create({
    moduleUUID = ModuleUUID,
    options = Options,
    runLocal = runService.Run,
    printWarning = ConsoleIO.PrintWarning,
    isServer = function()
        return Ext.IsServer() == true
    end,
    createChannel = function(moduleUUID, channelName)
        return Ext.Net.CreateChannel(moduleUUID, channelName)
    end,
})

---@param options table
---@return table
local function executeRun(options)
    local normalized = Options.Normalize(options or {})

    if normalized.help then
        ConsoleIO.PrintHelp(ConsoleIO.PrintLine, normalized.helpTopic)
        return ResultModel.Finalize(ResultModel.NewRun("unknown", normalized, 0), 0)
    end

    return ExecutionRouter.Run(normalized, {
        isClient = function()
            return Ext.IsClient() == true
        end,
        requestServerRun = serverRunChannel.RequestServerRun,
        runLocal = runService.Run,
        renderRun = function(run)
            ConsoleReporter.PrintRun(run, {
                printLine = ConsoleIO.PrintLine,
                printWarning = ConsoleIO.PrintWarning,
            })
        end,
        buildPendingRun = function(pendingOptions)
            local pending = ResultModel.NewRun("client", pendingOptions, 0)
            ResultModel.AddWarning(pending,
                "Server-context run requested from client; final result will print asynchronously.")
            return ResultModel.Finalize(pending, 0)
        end,
        printLine = ConsoleIO.PrintLine,
        printWarning = ConsoleIO.PrintWarning,
    })
end

---@param args any[]
---@param optionOverrides table|nil
---@return table
local function runFromArgs(args, optionOverrides)
    local parsed = Options.ParseArgs(args or {})
    if type(optionOverrides) == "table" then
        for key, value in pairs(optionOverrides) do
            parsed[key] = value
        end
    end

    return executeRun(parsed)
end

---@param metadata table|nil
---@param registerOptions table
---@return table
local function applyRegisterMetadata(metadata, registerOptions)
    local merged = {}
    if type(metadata) == "table" then
        for key, value in pairs(metadata) do
            merged[key] = value
        end
    end

    local mergedTags = {}
    local seenTags = {}
    if type(merged.tags) == "table" then
        for _, tag in ipairs(merged.tags) do
            if type(tag) == "string" and tag ~= "" then
                table.insert(mergedTags, tag)
                seenTags[string.lower(tag)] = true
            end
        end
    end
    for _, tag in ipairs(registerOptions.globalTags) do
        local normalizedTag = string.lower(tag)
        if seenTags[normalizedTag] ~= true then
            table.insert(mergedTags, tag)
            seenTags[normalizedTag] = true
        end
    end
    merged.tags = mergedTags

    if registerOptions.ownerModuleUUID ~= nil and
        (type(merged.ownerModuleUUID) ~= "string" or merged.ownerModuleUUID == "") then
        merged.ownerModuleUUID = registerOptions.ownerModuleUUID
    end

    return merged
end

---@param baseCallable function|table
---@param name string
---@param optionsOrCallback table|function
---@param maybeCallback function|nil
---@param registerOptions table
---@return any
local function callWithRegisterMetadata(baseCallable, name, optionsOrCallback, maybeCallback, registerOptions)
    if type(optionsOrCallback) == "function" and maybeCallback == nil then
        return baseCallable(name, applyRegisterMetadata(nil, registerOptions), optionsOrCallback)
    end

    if type(optionsOrCallback) == "table" and type(maybeCallback) == "function" then
        return baseCallable(name, applyRegisterMetadata(optionsOrCallback, registerOptions), maybeCallback)
    end

    return baseCallable(name, optionsOrCallback, maybeCallback)
end

---@param commandAlias string
---@param ownerModuleUUID string|nil
local function registerConsumerCommandAlias(commandAlias, ownerModuleUUID)
    local aliasRegistry = rawget(_G, CONSUMER_ALIAS_REGISTRY_KEY)
    if type(aliasRegistry) ~= "table" then
        aliasRegistry = {}
        rawset(_G, CONSUMER_ALIAS_REGISTRY_KEY, aliasRegistry)
    end

    local existingOwner = aliasRegistry[commandAlias]
    if existingOwner ~= nil then
        if existingOwner ~= (ownerModuleUUID or "") then
            ConsoleIO.PrintWarning(string.format(
                "[DribbleSpec] command alias '%s' already registered by another module; keeping first registration.",
                commandAlias))
        end
        return
    end

    Ext.RegisterConsoleCommand(commandAlias, function(...)
        runFromArgs({ ... }, {
            ownerModuleUUID = ownerModuleUUID,
        })
    end)
    aliasRegistry[commandAlias] = ownerModuleUUID or ""
end

---@param options table|nil
---@return table
local function normalizeRegisterOptions(options)
    if options == nil then
        options = {}
    end

    if type(options) ~= "table" then
        error("RegisterTestGlobals(options) expects a table when options are provided", 3)
    end

    local normalized = {
        globalTags = {},
        ownerModuleUUID = nil,
        commandAlias = nil,
    }

    local ownerModuleUUID = options.ownerModuleUUID
    if ownerModuleUUID == nil and type(ModuleUUID) == "string" and ModuleUUID ~= "" then
        ownerModuleUUID = ModuleUUID
    end
    if ownerModuleUUID ~= nil then
        if type(ownerModuleUUID) ~= "string" or ownerModuleUUID == "" then
            error("RegisterTestGlobals(options) ownerModuleUUID must be a non-empty string", 3)
        end
        normalized.ownerModuleUUID = ownerModuleUUID
    end

    if options.globalTags ~= nil then
        if type(options.globalTags) ~= "table" then
            error("RegisterTestGlobals(options) globalTags must be an array of strings", 3)
        end

        for index, tag in ipairs(options.globalTags) do
            if type(tag) ~= "string" or tag == "" then
                error(string.format("RegisterTestGlobals(options) globalTags[%d] must be a non-empty string", index), 3)
            end
            table.insert(normalized.globalTags, tag)
        end
    end

    if options.commandAlias ~= nil then
        if type(options.commandAlias) ~= "string" then
            error("RegisterTestGlobals(options) commandAlias must be a string", 3)
        end

        local alias = string.match(options.commandAlias, "^%s*(.-)%s*$")
        if alias == nil or alias == "" then
            error("RegisterTestGlobals(options) commandAlias must not be empty", 3)
        end

        alias = string.lower(alias)
        if RESERVED_COMMAND_NAMES[alias] == true then
            error(string.format("RegisterTestGlobals(options) commandAlias '%s' is reserved", alias), 3)
        end

        if string.match(alias, "^[%w_%-]+$") == nil then
            error("RegisterTestGlobals(options) commandAlias may only contain letters, numbers, underscore, or hyphen", 3)
        end

        normalized.commandAlias = alias
    end

    return normalized
end

local function registerCommand()
    if rawget(_G, "__DRIBBLESPEC_COMMAND_REGISTERED") then
        return
    end

    Ext.RegisterConsoleCommand("dribbles", function(...)
        runFromArgs({ ... })
    end)

    Ext.RegisterConsoleCommand("d", function(...)
        runFromArgs({ ... })
    end)

    rawset(_G, "__DRIBBLESPEC_COMMAND_REGISTERED", true)
end

local function notAvailable(name)
    error(string.format("DribbleSpec Phase 8: '%s' is not implemented yet.", name), 2)
end

ApiBinder.Bind(DribbleSpec, registry)

DribbleSpec.Run = runService.Run
DribbleSpec.RunFromArgs = runFromArgs
DribbleSpec.expect = Expect.Expect
DribbleSpec.entityRef = EntityRef.Create
DribbleSpec.skip = SkipSignal.Throw
local function registerTestGlobals(options)
    local registerOptions = normalizeRegisterOptions(options)

    local symbols = PublicSymbols.Resolve(DribbleSpec)
    local exported = {}
    for _, symbolName in ipairs(PublicSymbols.Keys()) do
        exported[symbolName] = symbols[symbolName]
    end

    exported.describe = function(name, optionsOrCallback, maybeCallback)
        return callWithRegisterMetadata(symbols.describe, name, optionsOrCallback, maybeCallback, registerOptions)
    end

    exported.test = setmetatable({
        skip = function(name, optionsOrCallback, maybeCallback)
            return callWithRegisterMetadata(symbols.test.skip, name, optionsOrCallback, maybeCallback, registerOptions)
        end,
        only = function(name, optionsOrCallback, maybeCallback)
            return callWithRegisterMetadata(symbols.test.only, name, optionsOrCallback, maybeCallback, registerOptions)
        end,
    }, {
        __call = function(_, name, optionsOrCallback, maybeCallback)
            return callWithRegisterMetadata(symbols.test, name, optionsOrCallback, maybeCallback, registerOptions)
        end,
    })
    exported.it = exported.test

    exported.RunMine = function(runOptions)
        if runOptions ~= nil and type(runOptions) ~= "table" then
            error("RunMine(options) expects a table when options are provided", 2)
        end

        local optionsWithOwner = {}
        if type(runOptions) == "table" then
            for key, value in pairs(runOptions) do
                optionsWithOwner[key] = value
            end
        end
        optionsWithOwner.ownerModuleUUID = registerOptions.ownerModuleUUID

        return runService.Run(optionsWithOwner)
    end

    if registerOptions.commandAlias ~= nil then
        registerConsumerCommandAlias(registerOptions.commandAlias, registerOptions.ownerModuleUUID)
    end

    return exported
end

DribbleSpec.RegisterTestGlobals = registerTestGlobals

RegisterTestGlobals = registerTestGlobals

local globalRegisterTestGlobals = registerTestGlobals

rawset(_G, "RegisterTestGlobals", globalRegisterTestGlobals)

DribbleSpec.ResetRegistry = function()
    registry:Clear()
end
DribbleSpec.GetRegistry = function()
    return registry
end

DribbleSpec._internal = {
    registry = registry,
    notAvailable = notAvailable,
    expect = Expect.Expect,
    parseOptions = Options.ParseArgs,
    normalizeOptions = Options.Normalize,
    run = runService.Run,
    runFromArgs = runFromArgs,
    executeRun = executeRun,
    sandbox = Sandbox,
    clock = Clock,
}

registerCommand()
serverRunChannel.RegisterServerRunHandler()

return DribbleSpec
