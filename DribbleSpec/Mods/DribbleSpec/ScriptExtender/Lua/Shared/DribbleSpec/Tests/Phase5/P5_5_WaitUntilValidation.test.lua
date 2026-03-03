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

Dribble.describe("DribbleSpec Phase5 P5.5 waitUntil validation", { tags = { "unit", "phase5", "runtime" } }, function()
    Dribble.test("ctx.waitUntil requires opts.timeoutTicks positive integer", function(ctx)
        local err = captureError(function()
            ctx.waitUntil(function()
                return true
            end, {
                timeoutTicks = 0,
            })
        end)

        Assertions.Equals(type(err), "string", "validation should throw")
        Assertions.Contains(err, "timeoutTicks", "validation message")
    end)
end)
