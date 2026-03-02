local MODVERSION = Ext.Mod.GetMod(ModuleUUID).Info.ModVersion

if MODVERSION == nil then
    DSPrint(0, "DribbleSpec loaded (version unknown)")
else
    table.remove(MODVERSION)

    local versionNumber = table.concat(MODVERSION, ".")
    DSPrint(0, "DribbleSpec (client) version " .. versionNumber .. " loaded")
end
