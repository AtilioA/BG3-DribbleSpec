local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

Dribble.describe("DribbleSpec Phase8 P8.3 RegisterTestGlobals side effects", { tags = { "unit", "phase8", "consumer" } },
    function()
        Dribble.test("RegisterTestGlobals does not mutate _G or Mods", function()
            local originalDescribe = rawget(_G, "describe")
            local originalTest = rawget(_G, "test")
            local originalMods = rawget(_G, "Mods")

            local exports = RegisterTestGlobals()

            Assertions.Equals(type(exports.describe), "function", "export describe type")
            Assertions.Equals(type(exports.test), "table", "export test type")
            Assertions.Equals(rawget(_G, "describe"), originalDescribe, "global describe unchanged")
            Assertions.Equals(rawget(_G, "test"), originalTest, "global test unchanged")
            Assertions.Equals(rawget(_G, "Mods"), originalMods, "Mods table unchanged")
        end)

        Dribble.test("RegisterTestGlobals rejects arguments", function()
            local ok, err = xpcall(function()
                RegisterTestGlobals({})
            end, debug.traceback)

            Assertions.Equals(ok, false, "argument validation status")
            Assertions.Contains(err, "does not accept arguments", "argument validation message")
        end)
    end)
