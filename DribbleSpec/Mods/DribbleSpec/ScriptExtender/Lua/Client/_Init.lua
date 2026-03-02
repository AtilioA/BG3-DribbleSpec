MCM.SetKeybindingCallback('keybinding_setting_id', function()
    Ext.Net.PostMessageToServer("DS_trigger_callback_on_server", Ext.Json.Stringify({ skipChecks = false }))
end)

local MODVERSION = Ext.Mod.GetMod(ModuleUUID).Info.ModVersion

if MODVERSION == nil then
    DSPrint(0, "DribbleSpec loaded (version unknown)")
else
    table.remove(MODVERSION)

    local versionNumber = table.concat(MODVERSION, ".")
    DSPrint(0, "DribbleSpec (client) version " .. versionNumber .. " loaded")
end
