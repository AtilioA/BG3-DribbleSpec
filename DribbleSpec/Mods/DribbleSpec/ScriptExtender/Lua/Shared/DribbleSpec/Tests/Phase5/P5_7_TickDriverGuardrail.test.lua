local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RuntimeHelpers = Ext.Require("Shared/DribbleSpec/Runtime/Helpers.lua")

Dribble.describe("DribbleSpec Phase5 P5.7 tick driver guardrail", { tags = { "unit", "phase5", "runtime" } }, function()
    Dribble.test("waitUntil advances by injected tick driver deterministically", function()
        local tickCalls = 0
        local checks = 0
        local helpers = RuntimeHelpers.Create({
            context = "client",
            tickDriver = function()
                tickCalls = tickCalls + 1
                return true
            end,
        })

        local ok, elapsedTicks = helpers.waitUntil(function()
            checks = checks + 1
            return checks >= 4
        end, {
            timeoutTicks = 10,
        })

        Assertions.Equals(ok, true, "waitUntil success")
        Assertions.Equals(elapsedTicks, 3, "elapsed ticks")
        Assertions.Equals(tickCalls, 3, "tick driver calls")
    end)
end)
