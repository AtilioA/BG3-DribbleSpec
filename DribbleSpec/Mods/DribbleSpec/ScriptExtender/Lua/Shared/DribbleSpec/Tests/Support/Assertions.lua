local Assertions = {}

---@param actual any
---@param expected any
---@param label string
function Assertions.Equals(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", tostring(label), tostring(expected), tostring(actual)))
    end
end

---@param value string
---@param needle string
---@param label string
function Assertions.Contains(value, needle, label)
    local haystack = tostring(value)
    local token = tostring(needle)
    if not string.find(haystack, token, 1, true) then
        error(string.format("%s: expected '%s' to contain '%s'", tostring(label), haystack, token))
    end
end

return Assertions
