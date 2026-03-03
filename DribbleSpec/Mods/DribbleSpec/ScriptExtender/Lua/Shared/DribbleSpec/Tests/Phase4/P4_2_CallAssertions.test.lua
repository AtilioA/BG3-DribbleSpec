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

Dribble.describe("DribbleSpec Phase4 P4.2 call assertions", { tags = { "unit", "phase4", "doubles" } }, function()
    Dribble.test("toHaveBeenCalledTimes validates exact invocation count", function(ctx)
        local spy = ctx.mockFn()
        spy("a")
        spy("b")

        ctx.expect(spy).toHaveBeenCalledTimes(2)

        local mismatchErr = captureError(function()
            ctx.expect(spy).toHaveBeenCalledTimes(3)
        end)
        Assertions.Equals(type(mismatchErr), "string", "count mismatch should throw")
    end)

    Dribble.test("toHaveBeenCalledWith validates call arguments with deep equality", function(ctx)
        local spy = ctx.mockFn()
        spy(7, "alpha", {
            nested = {
                value = 42,
            },
        })

        ctx.expect(spy).toHaveBeenCalledWith(7, "alpha", {
            nested = {
                value = 42,
            },
        })

        local mismatchErr = captureError(function()
            ctx.expect(spy).toHaveBeenCalledWith(7, "alpha", {
                nested = {
                    value = 99,
                },
            })
        end)
        Assertions.Equals(type(mismatchErr), "string", "argument mismatch should throw")
    end)
end)
