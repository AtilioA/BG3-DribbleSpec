Ext.Require("Shared/DribbleSpec/init.lua")
local ok, err = pcall(function()
    Ext.Require("Shared/DribbleSpec/Tests/_Init.lua")
end)

if not ok then
    Ext.Utils.PrintWarning(string.format("[DribbleSpec] self-test preload skipped: %s", tostring(err)))
end

return Dribble
