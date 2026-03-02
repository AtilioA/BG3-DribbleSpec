local ManifestLoader = {}

---@param manifestPath string
---@return boolean loaded
---@return string|nil errorMessage
---@return any result
function ManifestLoader.TryLoad(manifestPath)
    if type(manifestPath) ~= "string" or manifestPath == "" then
        return false, "Manifest path is empty", nil
    end

    local ok, result = pcall(function()
        return Ext.Require(manifestPath)
    end)

    if not ok then
        return false, tostring(result), nil
    end

    return true, nil, result
end

return ManifestLoader
