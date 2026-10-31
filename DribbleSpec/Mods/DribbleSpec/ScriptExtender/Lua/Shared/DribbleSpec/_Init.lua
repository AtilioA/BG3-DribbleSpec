Ext.Require("Shared/DribbleSpec/init.lua")
Mutation = Ext.Require("Shared/DribbleSpec/Mutation/Agent.lua").Create({
    registry = DribbleSpec.GetRegistry(),
    run = DribbleSpec.Run,
})
-- BG3SE fires ResetCompleted once after a Lua reset, when all mods have loaded and session events have replayed; not on first load.
Ext.Events.ResetCompleted:Subscribe(function()
    Mutation.ResetCompleted = true
end)
local ok, err = pcall(function()
    Ext.Require("Shared/DribbleSpec/Tests/_Init.lua")
end)

if not ok then
    Ext.Utils.PrintWarning(string.format("[DribbleSpec] self-test preload skipped: %s", tostring(err)))
end

return DribbleSpec
