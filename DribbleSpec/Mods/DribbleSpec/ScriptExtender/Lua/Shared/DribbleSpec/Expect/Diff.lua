local Format = Ext.Require("Shared/DribbleSpec/Expect/Format.lua")

local Diff = {}

---@param detail table
---@return string
function Diff.FromMismatch(detail)
    local path = (detail and detail.path) or "$"
    local expected = Format.Value(detail and detail.expected)
    local actual = Format.Value(detail and detail.actual)
    return string.format("path=%s expected=%s actual=%s", tostring(path), expected, actual)
end

return Diff
