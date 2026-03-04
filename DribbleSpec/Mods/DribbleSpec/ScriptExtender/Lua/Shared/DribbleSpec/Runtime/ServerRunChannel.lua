local ServerRunChannel = {}

local DEFAULT_CHANNEL_NAME = "DribbleSpec_RunServer"
local REGISTERED_FLAG = "__DRIBBLESPEC_SERVER_RUN_HANDLER_REGISTERED"

---@class DribbleSpecServerRunChannelDeps
---@field moduleUUID string
---@field options table
---@field runLocal fun(options: table): table
---@field printWarning fun(message: string)
---@field isServer fun(): boolean
---@field createChannel fun(moduleUUID: string, channelName: string): table|nil

---@param deps DribbleSpecServerRunChannelDeps
---@param channelName string|nil
---@return table
function ServerRunChannel.Create(deps, channelName)
    local resolvedChannelName = channelName or DEFAULT_CHANNEL_NAME
    local channel = nil

    local function getChannel()
        if channel then
            return channel
        end

        if type(deps.createChannel) ~= "function" then
            return nil
        end

        channel = deps.createChannel(deps.moduleUUID, resolvedChannelName)
        return channel
    end

    local service = {}

    ---@param remoteOptions table
    ---@param onReply fun(response: table|nil)
    ---@return boolean
    function service.RequestServerRun(remoteOptions, onReply)
        local current = getChannel()
        if not current or type(current.RequestToServer) ~= "function" then
            deps.printWarning("[DribbleSpec] Server run channel unavailable on client.")
            onReply(nil)
            return false
        end

        current:RequestToServer({
            options = remoteOptions,
        }, function(response)
            onReply(response)
        end)

        return true
    end

    ---@return boolean
    function service.RegisterServerRunHandler()
        if rawget(_G, REGISTERED_FLAG) then
            return true
        end

        if deps.isServer() ~= true then
            return false
        end

        local current = getChannel()
        if not current or type(current.SetRequestHandler) ~= "function" then
            return false
        end

        current:SetRequestHandler(function(data, _)
            local payload = type(data) == "table" and data or {}
            local remoteOptions = deps.options.Normalize(payload.options or {})
            remoteOptions.context = "server"

            local runResult = deps.runLocal(remoteOptions)
            return {
                runResult = runResult,
            }
        end)

        rawset(_G, REGISTERED_FLAG, true)
        return true
    end

    return service
end

return ServerRunChannel
