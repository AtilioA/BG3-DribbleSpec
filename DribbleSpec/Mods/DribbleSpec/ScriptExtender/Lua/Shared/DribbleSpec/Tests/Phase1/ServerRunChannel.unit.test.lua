local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local ServerRunChannel = Ext.Require("Shared/DribbleSpec/Runtime/ServerRunChannel.lua")

DribbleSpec.describe("DribbleSpec ServerRunChannel unit", { tags = { "unit", "phase1" } }, function()
    DribbleSpec.test("warns when client channel is unavailable", function()
        local warningMessage = nil
        local callbackPayload = nil

        local channel = ServerRunChannel.Create({
            moduleUUID = ModuleUUID,
            options = {
                Normalize = function(options)
                    return options
                end,
            },
            runLocal = function(_)
                return {}
            end,
            printWarning = function(message)
                warningMessage = message
            end,
            isServer = function()
                return false
            end,
            createChannel = function(_, _)
                return nil
            end,
        })

        local ok = channel.RequestServerRun({}, function(payload)
            callbackPayload = payload
        end)

        Assertions.Equals(ok, false, "request result")
        Assertions.Equals(callbackPayload, nil, "callback payload")
        Assertions.Contains(warningMessage, "Server run channel unavailable", "warning text")
    end)

    DribbleSpec.test("registers server handler and enforces server context", function()
        local capturedHandler = nil
        local seenContext = nil
        local previousFlag = rawget(_G, "__DRIBBLESPEC_SERVER_RUN_HANDLER_REGISTERED")
        rawset(_G, "__DRIBBLESPEC_SERVER_RUN_HANDLER_REGISTERED", nil)

        local channel = ServerRunChannel.Create({
            moduleUUID = ModuleUUID,
            options = {
                Normalize = function(options)
                    return options
                end,
            },
            runLocal = function(options)
                seenContext = options.context
                return { ok = true }
            end,
            printWarning = function(_)
            end,
            isServer = function()
                return true
            end,
            createChannel = function(_, _)
                return {
                    SetRequestHandler = function(self, handler)
                        capturedHandler = handler
                    end,
                }
            end,
        }, "DribbleSpec_RunServer_Unit")

        local registered = channel.RegisterServerRunHandler()
        Assertions.Equals(registered, true, "registered result")
        Assertions.Equals(type(capturedHandler), "function", "handler type")

        local response = capturedHandler({ options = { context = "client" } }, nil)
        Assertions.Equals(seenContext, "server", "run context")
        Assertions.Equals(response.runResult.ok, true, "response run result")

        rawset(_G, "__DRIBBLESPEC_SERVER_RUN_HANDLER_REGISTERED", previousFlag)
    end)
end)
