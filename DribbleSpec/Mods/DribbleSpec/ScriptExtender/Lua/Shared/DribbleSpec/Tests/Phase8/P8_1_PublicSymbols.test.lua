local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local PublicSymbols = Ext.Require("Shared/DribbleSpec/Core/PublicSymbols.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

---@param values any[]
---@param expected any
---@return boolean
local function contains(values, expected)
    for _, value in ipairs(values) do
        if value == expected then
            return true
        end
    end

    return false
end

Dribble.describe("DribbleSpec Phase8 P8.1 public symbol registry", { tags = { "unit", "phase8", "consumer" } },
    function()
        Dribble.test("PublicSymbols keys include all consumer-facing exports", function()
            local keys = PublicSymbols.Keys()

            for _, symbolName in ipairs({
                "RegisterTestGlobals",
                "describe",
                "test",
                "it",
                "beforeAll",
                "beforeEach",
                "afterEach",
                "afterAll",
                "expect",
                "entityRef",
            }) do
                if not contains(keys, symbolName) then
                    error(string.format("missing symbol key '%s'", tostring(symbolName)))
                end
            end
        end)

        Dribble.test("PublicSymbols resolves live API references", function()
            local symbols = PublicSymbols.Resolve(Dribble)

            Assertions.Equals(symbols.RegisterTestGlobals, Dribble.RegisterTestGlobals, "register globals symbol")
            Assertions.Equals(symbols.describe, Dribble.describe, "describe symbol")
            Assertions.Equals(symbols.test, Dribble.test, "test symbol")
            Assertions.Equals(symbols.it, Dribble.it, "it symbol")
            Assertions.Equals(symbols.expect, Dribble.expect, "expect symbol")
            Assertions.Equals(symbols.entityRef, Dribble.entityRef, "entityRef symbol")
        end)
    end)
