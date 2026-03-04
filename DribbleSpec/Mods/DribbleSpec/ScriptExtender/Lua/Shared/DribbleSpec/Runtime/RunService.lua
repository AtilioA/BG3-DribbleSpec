local RunService = {}

---@class DribbleRunServiceDeps
---@field registry table
---@field options table
---@field clock table
---@field runner table
---@field resultModel table
---@field callerMod table

---@param snapshot table|nil
---@return boolean
local function hasRegisteredSuites(snapshot)
    if type(snapshot) ~= "table" then
        return false
    end

    local suites = snapshot.suites
    if type(suites) ~= "table" then
        return false
    end

    return #suites > 0
end

---@param deps DribbleRunServiceDeps
---@return table
function RunService.Create(deps)
    local service = {}

    ---@param options table|nil
    ---@return table
    function service.Run(options)
        local normalized = deps.options.Normalize(options or {})
        local snapshot = nil
        if deps.registry and type(deps.registry.Snapshot) == "function" then
            snapshot = deps.registry:Snapshot()
        end

        local runResult = deps.runner.Run({
            registry = deps.registry,
            options = normalized,
            clock = deps.clock,
        })

        if not hasRegisteredSuites(snapshot) then
            deps.resultModel.AddWarning(runResult,
                "No tests registered; import your test files before running dribble.")
        end

        runResult.caller = {
            moduleUUID = normalized.callerModuleUUID,
            name = nil,
        }

        if normalized.callerModuleUUID then
            local callerName, warning = deps.callerMod.ResolveName(normalized.callerModuleUUID)
            runResult.caller.name = callerName
            if warning then
                deps.resultModel.AddWarning(runResult, warning)
            end
        end

        return runResult
    end

    return service
end

return RunService
