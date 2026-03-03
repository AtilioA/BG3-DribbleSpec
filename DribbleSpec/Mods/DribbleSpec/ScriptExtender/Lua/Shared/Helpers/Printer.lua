-- DSPrinter = Printer:New { Prefix = "DribbleSpec", ApplyColor = true, DebugLevel = MCM.Get("debug_level") }

-- -- Update the Printer debug level when the setting is changed, since the value is only used during the object's creation
-- Ext.ModEvents.BG3MCM['MCM_Setting_Saved']:Subscribe(function(payload)
--     if not payload or payload.modUUID ~= ModuleUUID or not payload.settingId then
--         return
--     end

--     if payload.settingId == "debug_level" then
--         DSDebug(0, "Setting debug level to " .. payload.value)
--         DSPrinter.DebugLevel = payload.value
--     end
-- end)

-- function DSPrint(debugLevel, ...)
--     DSPrinter:SetFontColor(0, 255, 255)
--     DSPrinter:Print(debugLevel, ...)
-- end

-- function DSTest(debugLevel, ...)
--     DSPrinter:SetFontColor(100, 200, 150)
--     DSPrinter:PrintTest(debugLevel, ...)
-- end

-- function DSDebug(debugLevel, ...)
--     DSPrinter:SetFontColor(200, 200, 0)
--     DSPrinter:PrintDebug(debugLevel, ...)
-- end

-- function DSWarn(debugLevel, ...)
--     DSPrinter:SetFontColor(255, 100, 50)
--     DSPrinter:PrintWarning(debugLevel, ...)
-- end

-- function DSDump(debugLevel, ...)
--     DSPrinter:SetFontColor(190, 150, 225)
--     DSPrinter:Dump(debugLevel, ...)
-- end

-- function DSDumpArray(debugLevel, ...)
--     DSPrinter:DumpArray(debugLevel, ...)
-- end
