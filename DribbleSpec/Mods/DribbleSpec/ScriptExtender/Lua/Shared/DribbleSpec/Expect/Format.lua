local Format = {}

---@param key any
---@return string
local function keySortToken(key)
    local keyType = type(key)
    if keyType == "string" then
        return "1:" .. key
    end

    if keyType == "number" then
        return string.format("0:%0.17g", key)
    end

    if keyType == "boolean" then
        return key and "2:true" or "2:false"
    end

    return keyType .. ":" .. tostring(key)
end

---@param value table
---@return any[]
local function sortedKeys(value)
    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end

    table.sort(keys, function(left, right)
        return keySortToken(left) < keySortToken(right)
    end)

    return keys
end

---@param value any
---@param state table|nil
---@return string
function Format.Value(value, state)
    local valueType = type(value)
    if valueType == "string" then
        return string.format("%q", value)
    end

    if valueType == "number" or valueType == "boolean" or value == nil then
        return tostring(value)
    end

    if valueType ~= "table" then
        return string.format("<%s:%s>", valueType, tostring(value))
    end

    local currentState = state or {
        seen = {},
        nextId = 1,
    }

    if currentState.seen[value] then
        return string.format("<cycle#%d>", currentState.seen[value])
    end

    local id = currentState.nextId
    currentState.nextId = id + 1
    currentState.seen[value] = id

    local parts = {}
    for _, key in ipairs(sortedKeys(value)) do
        local keyType = type(key)
        local keyText = nil
        if keyType == "string" and string.match(key, "^[_%a][_%w]*$") then
            keyText = key
        else
            keyText = string.format("[%s]", Format.Value(key, currentState))
        end

        local entry = string.format("%s=%s", keyText, Format.Value(value[key], currentState))
        table.insert(parts, entry)
    end

    return string.format("{%s}", table.concat(parts, ", "))
end

return Format
