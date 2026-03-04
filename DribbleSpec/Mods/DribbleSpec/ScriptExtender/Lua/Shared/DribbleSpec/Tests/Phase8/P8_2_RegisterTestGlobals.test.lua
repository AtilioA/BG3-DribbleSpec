local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

Dribble.describe("DribbleSpec Phase8 P8.2 RegisterTestGlobals", { tags = { "unit", "phase8", "consumer" } },
    function()
        Dribble.test("framework RegisterTestGlobals entrypoints are available", function()
            Assertions.Equals(type(rawget(_G, "RegisterTestGlobals")), "function", "global register function")
            Assertions.Equals(type(Dribble.RegisterTestGlobals), "function", "Dribble register function")
        end)

        Dribble.test("RegisterTestGlobals adds public symbols into target namespace", function()
            local target = RegisterTestGlobals()

            Assertions.Equals(type(target.describe), "function", "describe exposed")
            Assertions.Equals(type(target.test), "table", "test exposed")
            Assertions.Equals(type(target.it), "table", "it exposed")
            Assertions.Equals(type(target.beforeAll), "function", "beforeAll exposed")
            Assertions.Equals(type(target.afterAll), "function", "afterAll exposed")
            Assertions.Equals(type(target.expect), "function", "expect exposed")
            Assertions.Equals(type(target.entityRef), "function", "entityRef exposed")
            Assertions.Equals(type(target.RegisterTestGlobals), "function", "RegisterTestGlobals exposed")
        end)

        Dribble.test("RegisterTestGlobals returns fresh table snapshots", function()
            local first = RegisterTestGlobals()
            local second = RegisterTestGlobals()

            Assertions.Equals(first.describe, second.describe, "describe function identity")
            Assertions.Equals(first.test, second.test, "test function identity")
            Assertions.Equals(first == second, false, "separate export tables")
        end)
    end)
