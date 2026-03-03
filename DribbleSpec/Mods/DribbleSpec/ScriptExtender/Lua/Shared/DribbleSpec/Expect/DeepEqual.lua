local DeepEqual = {}

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

---@param path string
---@param key any
---@return string
local function appendPath(path, key)
    if type(key) == "string" and string.match(key, "^[_%a][_%w]*$") then
        return path .. "." .. key
    end

    return string.format("%s[%s]", path, tostring(key))
end

---@param expected any
---@param actual any
---@param path string
---@return boolean, table|nil
local function mismatch(expected, actual, path)
    return false, {
        path = path,
        expected = expected,
        actual = actual,
    }
end

---@param expected any
---@param actual any
---@param path string
---@param state table
---@return boolean, table|nil
local function compare(expected, actual, path, state)
    if expected == actual then
        return true, nil
    end

    local expectedType = type(expected)
    local actualType = type(actual)
    if expectedType ~= actualType then
        return mismatch(expected, actual, path)
    end

    if expectedType ~= "table" then
        return mismatch(expected, actual, path)
    end

    local seenByExpected = state.seen[expected]
    if seenByExpected and seenByExpected[actual] then
        return true, nil
    end

    if not seenByExpected then
        seenByExpected = {}
        state.seen[expected] = seenByExpected
    end
    seenByExpected[actual] = true

    local keySet = {}
    local keys = {}
    for key in pairs(expected) do
        if not keySet[key] then
            table.insert(keys, key)
            keySet[key] = true
        end
    end

    for key in pairs(actual) do
        if not keySet[key] then
            table.insert(keys, key)
            keySet[key] = true
        end
    end

    table.sort(keys, function(left, right)
        return keySortToken(left) < keySortToken(right)
    end)

    for _, key in ipairs(keys) do
        local expectedValue = expected[key]
        local actualValue = actual[key]
        if expectedValue == nil and actualValue ~= nil then
            return mismatch(expectedValue, actualValue, appendPath(path, key))
        end

        if expectedValue ~= nil and actualValue == nil then
            return mismatch(expectedValue, actualValue, appendPath(path, key))
        end

        local equal, detail = compare(expectedValue, actualValue, appendPath(path, key), state)
        if not equal then
            return false, detail
        end
    end

    return true, nil
end

---@param expected any
---@param actual any
---@return boolean, table|nil
function DeepEqual.Compare(expected, actual)
    return compare(expected, actual, "$", {
        seen = {},
    })
end

return DeepEqual
