local VolatileFilters = {}

local PRESETS = {
    entity = {
        keys = {
            CreationIndex = true,
            Entity = true,
            EntityHandle = true,
            Handle = true,
            NetID = true,
            NetId = true,
            NetworkId = true,
            ReplicationFlags = true,
            ReplicationMask = true,
            ReplicationState = true,
            RuntimeEntityId = true,
            Salt = true,
            TransientReplicationId = true,
        },
        prefixes = {
            "Replication",
            "Runtime",
            "Transient",
        },
    },
}

---@param presetName string
---@return table
local function requirePreset(presetName)
    local preset = PRESETS[presetName]
    if type(preset) ~= "table" then
        error(string.format("Unknown volatile preset '%s'", tostring(presetName)), 3)
    end

    return preset
end

---@param key any
---@param preset table
---@return boolean
local function shouldIgnoreKey(key, preset)
    if type(key) ~= "string" then
        return false
    end

    if preset.keys[key] then
        return true
    end

    for _, prefix in ipairs(preset.prefixes or {}) do
        if string.sub(key, 1, #prefix) == prefix then
            return true
        end
    end

    return false
end

---@param value any
---@param preset table
---@param seen table|nil
---@return any
local function sanitizeValue(value, preset, seen)
    if type(value) ~= "table" then
        return value
    end

    local refs = seen or {}
    if refs[value] ~= nil then
        return refs[value]
    end

    local clone = {}
    refs[value] = clone

    for key, entry in pairs(value) do
        if not shouldIgnoreKey(key, preset) then
            clone[sanitizeValue(key, preset, refs)] = sanitizeValue(entry, preset, refs)
        end
    end

    return clone
end

---@param value any
---@param presetName string|nil
---@return any
function VolatileFilters.ApplyPreset(value, presetName)
    if presetName == nil or presetName == "" then
        return value
    end

    if type(presetName) ~= "string" then
        error("volatilePreset must be a string", 3)
    end

    local preset = requirePreset(presetName)
    return sanitizeValue(value, preset)
end

return VolatileFilters
