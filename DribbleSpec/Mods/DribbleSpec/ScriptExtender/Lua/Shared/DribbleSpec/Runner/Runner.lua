local ResultModel = Ext.Require("Lib/DribbleSpec/Core/ResultModel.lua")

local Runner = {}

---@return string
function Runner.DetectContext()
    if type(Ext) ~= "table" then
        return "unknown"
    end

    if type(Ext.IsClient) == "function" and Ext.IsClient() then
        return "client"
    end

    if type(Ext.IsServer) == "function" and Ext.IsServer() then
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

    local run = ResultModel.NewRun(Runner.DetectContext(), options, nowMs())

    local snapshot = { suites = {} }
    if registry and type(registry.Snapshot) == "function" then
        snapshot = registry:Snapshot()
    end

    for _, suite in ipairs(snapshot.suites or {}) do
        table.insert(run.suites, {
            name = suite.name,
            tags = (suite.metadata and suite.metadata.tags) or {},
            durationMs = 0,
            tests = {},
        })
    end

    return ResultModel.Finalize(run, nowMs())
end

return Runner
