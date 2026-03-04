local ExecutionRouter = {}

---@class DribbleSpecExecutionRouterDeps
---@field isClient fun(): boolean
---@field requestServerRun fun(options: table, onReply: fun(response: table|nil))
---@field runLocal fun(options: table): table
---@field renderRun fun(runResult: table)
---@field buildPendingRun fun(options: table): table
---@field printLine fun(message: string)
---@field printWarning fun(message: string)

---@param options table
---@param deps DribbleSpecExecutionRouterDeps
---@return table
function ExecutionRouter.Run(options, deps)
    local targetContext = tostring(options.context or "any")
    if targetContext == "server" and deps.isClient() then
        deps.requestServerRun(options, function(response)
            if type(response) == "table" and type(response.runResult) == "table" then
                deps.renderRun(response.runResult)
                return
            end

            deps.printWarning("[DribbleSpec] Invalid server run response.")
        end)

        deps.printLine("[DribbleSpec] Requested server-context run from client; awaiting server response...")
        return deps.buildPendingRun(options)
    end

    local runResult = deps.runLocal(options)
    deps.renderRun(runResult)
    return runResult
end

return ExecutionRouter
