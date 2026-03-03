local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

Dribble.describe("DribbleSpec Phase4 P4.4 spyOn", { tags = { "unit", "phase4", "doubles" } }, function()
    Dribble.test("ctx.spyOn wraps existing function, records calls, and preserves original behavior", function(ctx)
        local target = {
            sum = function(a, b)
                return a + b
            end,
        }

        local spy = ctx.spyOn(target, "sum")
        Assertions.Equals(type(spy), "function", "spy type")
        Assertions.Equals(target.sum, spy, "target method replaced with spy")

        local value = target.sum(2, 3)
        Assertions.Equals(value, 5, "spy preserves original implementation")

        ctx.expect(spy).toHaveBeenCalledTimes(1)
        ctx.expect(spy).toHaveBeenCalledWith(2, 3)
    end)
end)
