local RunService = {}

---@class DribbleRunServiceDeps
---@field registry table
---@field options table
---@field clock table
---@field runner table
---@field resultModel table
---@field callerMod table
---@field manifestLoader table

---@param deps DribbleRunServiceDeps
---@return table
function RunService.Create(deps)
    local loadedManifests = {}

    ---@param manifestPath string
    ---@param forceReload boolean|nil
    ---@return boolean loaded
    ---@return string|nil errorMessage
    ---@return boolean attempted
    local function loadManifest(manifestPath, forceReload)
        if forceReload ~= true and loadedManifests[manifestPath] == true then
            return true, nil, false
        end

        local loaded, err = deps.manifestLoader.TryLoad(manifestPath)
        if loaded then
            loadedManifests[manifestPath] = true
        end

        return loaded, err, true
    end

    local service = {}

    ---@param options table|nil
    ---@return table
    function service.Run(options)
        local normalized = deps.options.Normalize(options or {})
        local loaded, manifestError, manifestAttempted = loadManifest(normalized.manifestPath,
            normalized.reloadManifest == true)

        local runResult = deps.runner.Run({
            registry = deps.registry,
            options = normalized,
            clock = deps.clock,
        })

        runResult.manifest = {
            path = normalized.manifestPath,
            attempted = manifestAttempted,
            loaded = loaded,
            error = manifestError,
        }

        if manifestAttempted and not loaded then
            deps.resultModel.AddWarning(runResult,
                string.format("Manifest not loaded from '%s': %s", tostring(normalized.manifestPath), tostring(manifestError)))
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

    service.LoadManifest = loadManifest
    return service
end

return RunService
