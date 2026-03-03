local Expect = {}
local Format = Ext.Require("Shared/DribbleSpec/Expect/Format.lua")
local DeepEqual = Ext.Require("Shared/DribbleSpec/Expect/DeepEqual.lua")
local Diff = Ext.Require("Shared/DribbleSpec/Expect/Diff.lua")

---@param matcherName string
---@param message string
local function fail(matcherName, message)
    error(string.format("expect.%s failed: %s", tostring(matcherName), tostring(message)), 3)
end

---@param value any
---@return string
local function renderValue(value)
    return Format.Value(value)
end

---@param haystack any
---@param needle any
---@return boolean
local function arrayContains(haystack, needle)
    for i = 1, #haystack do
        local equal = DeepEqual.Compare(needle, haystack[i])
        if equal then
            return true
        end
    end

    return false
end

---@param fn any
---@return boolean, string
local function captureThrownError(fn)
    if type(fn) ~= "function" then
        return false, "value must be a function"
    end

    local ok, err = xpcall(function()
        fn()
    end, debug.traceback)

    if ok then
        return false, "function did not throw"
    end

    return true, tostring(err)
end

---@param actual any
---@return table
function Expect.Create(actual)
    return {
        toBe = function(expected)
            if actual ~= expected then
                fail("toBe", string.format("expected=%s actual=%s", tostring(expected), tostring(actual)))
            end
        end,
        toBeNil = function()
            if actual ~= nil then
                fail("toBeNil", string.format("expected nil, actual=%s", renderValue(actual)))
            end
        end,
        toBeTruthy = function()
            if not actual then
                fail("toBeTruthy", string.format("expected truthy value, actual=%s", renderValue(actual)))
            end
        end,
        toBeFalsy = function()
            if actual ~= nil and actual ~= false then
                fail("toBeFalsy", string.format("expected falsy value, actual=%s", renderValue(actual)))
            end
        end,
        toContain = function(needle)
            if type(actual) == "string" then
                local token = tostring(needle)
                if string.find(actual, token, 1, true) == nil then
                    fail("toContain", string.format("expected string to contain '%s'", token))
                end
                return
            end

            if type(actual) == "table" then
                if not arrayContains(actual, needle) then
                    fail("toContain", string.format("expected array table to contain %s", renderValue(needle)))
                end
                return
            end

            fail("toContain", string.format("unsupported container type '%s'", type(actual)))
        end,
        toEqual = function(expected)
            local equal, detail = DeepEqual.Compare(expected, actual)
            if not equal then
                fail("toEqual", Diff.FromMismatch(detail))
            end
        end,
        toThrow = function()
            local thrown, message = captureThrownError(actual)
            if not thrown then
                fail("toThrow", message)
            end
        end,
        toThrowMatch = function(pattern)
            local thrown, message = captureThrownError(actual)
            if not thrown then
                fail("toThrowMatch", message)
            end

            local normalizedPattern = tostring(pattern or "")
            if normalizedPattern == "" then
                fail("toThrowMatch", "pattern must be a non-empty Lua pattern")
            end

            if not string.match(message, normalizedPattern) then
                fail("toThrowMatch",
                    string.format("error '%s' does not match Lua pattern '%s'", message, normalizedPattern))
            end
        end,
    }
end

---@param actual any
---@return table
function Expect.Expect(actual)
    return Expect.Create(actual)
end

return Expect
