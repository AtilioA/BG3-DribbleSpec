local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

---@param fn function
---@return string|nil
local function captureError(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        return nil
    end

    return tostring(err)
end

Dribble.describe("DribbleSpec Phase5 P5.6 waitUntil behavior", { tags = { "unit", "phase5", "runtime" } }, function()
    Dribble.test("ctx.waitUntil succeeds when predicate becomes true before timeout", function(ctx)
        local calls = 0
        local ok, elapsedTicks = ctx.waitUntil(function()
            calls = calls + 1
            return calls >= 3
        end, {
            timeoutTicks = 5,
        })

        Assertions.Equals(ok, true, "waitUntil success")
        Assertions.Equals(elapsedTicks, 2, "elapsed ticks")
        Assertions.Equals(calls, 3, "predicate calls")
    end)

    Dribble.test("ctx.waitUntil times out deterministically after timeoutTicks", function(ctx)
        local calls = 0
        local err = captureError(function()
            ctx.waitUntil(function()
                calls = calls + 1
                return false
            end, {
                timeoutTicks = 2,
            })
        end)

        Assertions.Equals(type(err), "string", "timeout should throw")
        Assertions.Contains(err, "timed out", "timeout message")
        Assertions.Contains(err, "2 ticks", "timeout budget in message")
        Assertions.Equals(calls, 3, "deterministic predicate call count")
    end)
end)
