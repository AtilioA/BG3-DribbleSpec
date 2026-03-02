local CallerMod = {}

---@param moduleUUID string|nil
---@return string callerName
---@return string|nil warning
function CallerMod.ResolveName(moduleUUID)
    if type(moduleUUID) ~= "string" or moduleUUID == "" then
        return "UnknownMod", "Caller module UUID not provided"
    end

    if type(Ext) ~= "table" or type(Ext.Mod) ~= "table" or type(Ext.Mod.GetMod) ~= "function" then
        return "UnknownMod", "Ext.Mod.GetMod unavailable"
    end

    local mod = Ext.Mod.GetMod(moduleUUID)
    if not mod or type(mod.Info) ~= "table" or type(mod.Info.Name) ~= "string" or mod.Info.Name == "" then
        return "UnknownMod", "No mod info found for module UUID: " .. moduleUUID
    end

    return mod.Info.Name, nil
end

---@param value string
---@return string
function CallerMod.ToFileSafeName(value)
    local safe = tostring(value or "UnknownMod")
    safe = safe:gsub("[^%w%-%._]", "_")
    if safe == "" then
        safe = "UnknownMod"
    end
    return safe
end

return CallerMod
