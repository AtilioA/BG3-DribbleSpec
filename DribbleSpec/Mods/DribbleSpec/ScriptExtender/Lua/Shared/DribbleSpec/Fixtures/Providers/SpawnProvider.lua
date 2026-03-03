local SpawnProvider = {}
SpawnProvider.__index = SpawnProvider

---@param params table|nil
---@return table
function SpawnProvider.Create(params)
    local resolvedParams = params or {}

    return setmetatable({
        name = "spawn",
        _spawner = resolvedParams.spawner,
    }, SpawnProvider)
end

---@param kind string
---@param spec table
---@param context table
---@return table|nil, string|nil
function SpawnProvider:Resolve(kind, spec, context)
    if type(spec) ~= "table" then
        return nil, nil
    end

    local spawnFn = nil
    if type(spec.spawn) == "function" then
        spawnFn = spec.spawn
    elseif type(self._spawner) == "function" then
        spawnFn = self._spawner
    end

    if type(spawnFn) ~= "function" then
        return nil, nil
    end

    local ok, spawnedOrErr = pcall(spawnFn, spec, context, kind)
    if not ok then
        return nil, tostring(spawnedOrErr)
    end

    if spawnedOrErr == nil then
        return nil, nil
    end

    local handle = nil
    if type(spawnedOrErr) == "table" then
        handle = spawnedOrErr
    else
        handle = {
            value = spawnedOrErr,
        }
    end

    if type(handle.teardown) ~= "function" and type(spec.cleanup) == "function" then
        handle.teardown = spec.cleanup
    end

    return handle, nil
end

return SpawnProvider
