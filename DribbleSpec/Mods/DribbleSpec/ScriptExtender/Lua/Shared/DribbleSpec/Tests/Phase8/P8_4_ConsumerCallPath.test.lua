local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

Dribble.describe("DribbleSpec Phase8 P8.4 consumer call path", { tags = { "unit", "phase8", "consumer" } },
    function()
        Dribble.test("consumer can assign returned exports to custom namespace", function()
            local consumerDribbles = RegisterTestGlobals()

            Assertions.Equals(type(consumerDribbles), "table", "consumer namespace table")
            Assertions.Equals(type(consumerDribbles.test), "table", "test symbol exported")
            Assertions.Equals(type(consumerDribbles.beforeEach), "function", "beforeEach symbol exported")
            Assertions.Equals(type(consumerDribbles.expect), "function", "expect symbol exported")
        end)
    end)
