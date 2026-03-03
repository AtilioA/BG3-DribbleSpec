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

Dribble.describe("DribbleSpec Phase4 P4.3 call subset match", { tags = { "unit", "phase4", "doubles" } }, function()
    Dribble.test("toHaveBeenCalledWithMatch matches subset on any table argument in any call", function(ctx)
        local spy = ctx.mockFn()
        spy("ignored", {
            kind = "combat",
            payload = {
                id = 7,
                source = "ui",
            },
            tags = { "alpha", "beta" },
        }, 123)
        spy({
            kind = "other",
        })

        ctx.expect(spy).toHaveBeenCalledWithMatch({
            payload = {
                id = 7,
            },
        })

        local mismatchErr = captureError(function()
            ctx.expect(spy).toHaveBeenCalledWithMatch({
                payload = {
                    missing = true,
                },
            })
        end)
        Assertions.Equals(type(mismatchErr), "string", "subset mismatch should throw")
    end)
end)
