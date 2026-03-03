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

Dribble.describe("DribbleSpec Phase4 P4.5 stub", { tags = { "unit", "phase4", "doubles" } }, function()
    Dribble.test("ctx.stub replaces existing function implementation and records calls", function(ctx)
        local target = {
            sum = function(a, b)
                return a + b
            end,
        }

        local stub = ctx.stub(target, "sum", function(a, b)
            return a * b
        end)

        Assertions.Equals(type(stub), "function", "stub type")
        Assertions.Equals(target.sum, stub, "target method replaced with stub")

        local value = target.sum(2, 3)
        Assertions.Equals(value, 6, "stub implementation result")

        ctx.expect(stub).toHaveBeenCalledTimes(1)
        ctx.expect(stub).toHaveBeenCalledWith(2, 3)
    end)

    Dribble.test("ctx.stub enforces existing target function", function(ctx)
        local target = {}
        local err = captureError(function()
            ctx.stub(target, "missing", function()
                return true
            end)
        end)

        Assertions.Equals(type(err), "string", "missing function should throw")
        Assertions.Contains(err, "existing function", "error message")
    end)
end)
