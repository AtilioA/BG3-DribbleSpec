local Registry = Ext.Require("Shared/DribbleSpec/Core/Registry.lua")
local ApiBinder = Ext.Require("Shared/DribbleSpec/Core/ApiBinder.lua")
local PublicSymbols = Ext.Require("Shared/DribbleSpec/Core/PublicSymbols.lua")
local ResultModel = Ext.Require("Shared/DribbleSpec/Core/ResultModel.lua")
local Runner = Ext.Require("Shared/DribbleSpec/Runner/Runner.lua")
local Options = Ext.Require("Shared/DribbleSpec/Runner/Options.lua")
local Clock = Ext.Require("Shared/DribbleSpec/Internal/Clock.lua")
local Sandbox = Ext.Require("Shared/DribbleSpec/Internal/Sandbox.lua")
local CallerMod = Ext.Require("Shared/DribbleSpec/Internal/CallerMod.lua")
local ConsoleIO = Ext.Require("Shared/DribbleSpec/Internal/ConsoleIO.lua")
local ConsoleReporter = Ext.Require("Shared/DribbleSpec/Reporters/ConsoleReporter.lua")
local ExecutionRouter = Ext.Require("Shared/DribbleSpec/Runtime/ExecutionRouter.lua")
local RunService = Ext.Require("Shared/DribbleSpec/Runtime/RunService.lua")
local ServerRunChannel = Ext.Require("Shared/DribbleSpec/Runtime/ServerRunChannel.lua")
local Expect = Ext.Require("Shared/DribbleSpec/Expect/Expect.lua")
local EntityRef = Ext.Require("Shared/DribbleSpec/Entity/EntityRef.lua")

---@class DribbleSpecAPI
---@field _VERSION string
---@field _PHASE integer
---@field _internal table
local Dribble = {
    _VERSION = "0.8.0-phase8",
    _PHASE = 8,
}

_G.Dribble = Dribble

local registry = Registry.Create()
local runService = RunService.Create({
    registry = registry,
    options = Options,
    clock = Clock,
    runner = Runner,
    resultModel = ResultModel,
    callerMod = CallerMod,
})

local serverRunChannel = ServerRunChannel.Create({
    moduleUUID = ModuleUUID,
    options = Options,
    runLocal = runService.Run,
    printWarning = ConsoleIO.PrintWarning,
    isServer = function()
        return type(Ext) == "table" and type(Ext.IsServer) == "function" and Ext.IsServer() == true
    end,
    createChannel = function(moduleUUID, channelName)
        if type(Ext) ~= "table" or type(Ext.Net) ~= "table" or type(Ext.Net.CreateChannel) ~= "function" then
            return nil
        end

        return Ext.Net.CreateChannel(moduleUUID, channelName)
    end,
})

---@param args any[]
---@return table
local function runFromArgs(args)
    local options = Options.ParseArgs(args or {})

    if options.help then
        ConsoleIO.PrintHelp(ConsoleIO.PrintLine, options.helpTopic)
        return ResultModel.Finalize(ResultModel.NewRun("unknown", options, 0), 0)
    end

    return ExecutionRouter.Run(options, {
        isClient = function()
            return type(Ext) == "table" and type(Ext.IsClient) == "function" and Ext.IsClient() == true
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
    error(string.format("DribbleSpec Phase 8: '%s' is not implemented yet.", name), 2)
end

ApiBinder.Bind(Dribble, registry)

Dribble.Run = runService.Run
Dribble.RunFromArgs = runFromArgs
Dribble.expect = Expect.Expect
Dribble.entityRef = EntityRef.Create
local function registerTestGlobals(options)
    if options ~= nil then
        error("RegisterTestGlobals() does not accept arguments", 2)
    end

    local symbols = PublicSymbols.Resolve(Dribble)
    local exported = {}
    for _, symbolName in ipairs(PublicSymbols.Keys()) do
        exported[symbolName] = symbols[symbolName]
    end

    return exported
end

Dribble.RegisterTestGlobals = registerTestGlobals

RegisterTestGlobals = registerTestGlobals

local globalRegisterTestGlobals = registerTestGlobals

rawset(_G, "RegisterTestGlobals", globalRegisterTestGlobals)

Dribble.ResetRegistry = function()
    registry:Clear()
end
Dribble.GetRegistry = function()
    return registry
end

Dribble._internal = {
    registry = registry,
    notAvailable = notAvailable,
    expect = Expect.Expect,
    parseOptions = Options.ParseArgs,
    normalizeOptions = Options.Normalize,
    run = runService.Run,
    runFromArgs = runFromArgs,
    sandbox = Sandbox,
    clock = Clock,
    resolveCallerName = CallerMod.ResolveName,
    makeFileSafeName = CallerMod.ToFileSafeName,
}

registerCommand()
serverRunChannel.RegisterServerRunHandler()

return Dribble
