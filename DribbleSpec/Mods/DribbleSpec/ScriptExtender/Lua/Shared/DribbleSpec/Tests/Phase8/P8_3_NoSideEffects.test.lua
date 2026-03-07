local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

DribbleSpec.describe("DribbleSpec Phase8 P8.3 RegisterTestGlobals side effects", { tags = { "unit", "phase8", "consumer" } },
    function()
        DribbleSpec.test("RegisterTestGlobals does not mutate _G or Mods", function()
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

        DribbleSpec.test("RegisterTestGlobals rejects invalid options", function()
            local ok, err = xpcall(function()
                RegisterTestGlobals("bad options")
            end, debug.traceback)

            Assertions.Equals(ok, false, "argument validation status")
            Assertions.Contains(err, "expects a table", "argument validation message")
        end)

        DribbleSpec.test("RegisterTestGlobals commandAlias requires explicit ownerModuleUUID", function()
            local ok, err = xpcall(function()
                RegisterTestGlobals({
                    commandAlias = "mytests",
                })
            end, debug.traceback)

            Assertions.Equals(ok, false, "missing owner status")
            Assertions.Contains(err, "commandAlias requires ownerModuleUUID", "missing owner message")
        end)

        DribbleSpec.test("RegisterTestGlobals commandAlias registers once", function()
            local originalAliasRegistry = rawget(_G, "__DRIBBLESPEC_CONSUMER_COMMAND_ALIASES")

            local ok, err = xpcall(function()
                rawset(_G, "__DRIBBLESPEC_CONSUMER_COMMAND_ALIASES", nil)

                RegisterTestGlobals({
                    ownerModuleUUID = "module-a",
                    commandAlias = "mytests",
                })

                local aliasRegistry = rawget(_G, "__DRIBBLESPEC_CONSUMER_COMMAND_ALIASES")
                Assertions.Equals(type(aliasRegistry), "table", "alias registry created")
                Assertions.Equals(aliasRegistry.mytests, "module-a", "alias owner set")

                RegisterTestGlobals({
                    ownerModuleUUID = "module-a",
                    commandAlias = "mytests",
                })

                RegisterTestGlobals({
                    ownerModuleUUID = "module-b",
                    commandAlias = "mytests",
                })

                local registrationCount = 0
                for _ in pairs(aliasRegistry) do
                    registrationCount = registrationCount + 1
                end
                Assertions.Equals(registrationCount, 1, "single alias registration")
                Assertions.Equals(aliasRegistry.mytests, "module-a", "first owner preserved")
            end, debug.traceback)

            rawset(_G, "__DRIBBLESPEC_CONSUMER_COMMAND_ALIASES", originalAliasRegistry)

            if not ok then
                error(err)
            end
        end)
    end)
