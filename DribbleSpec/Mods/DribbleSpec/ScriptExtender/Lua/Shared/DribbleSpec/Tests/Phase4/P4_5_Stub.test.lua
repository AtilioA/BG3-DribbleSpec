local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
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

DribbleSpec.describe("DribbleSpec Phase4 P4.5 stub", { tags = { "unit", "phase4", "doubles" } }, function()
    DribbleSpec.test("ctx.stub replaces existing function implementation and records calls", function(ctx)
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

    DribbleSpec.test("ctx.stub enforces existing target function", function(ctx)
        local target = {}
        local err = captureError(function()
            ctx.stub(target, "missing", function()
                return true
            end)
        end)

        Assertions.Equals(type(err), "string", "missing function should throw")
        Assertions.Contains(err, "existing function", "error message")
    end)

    DribbleSpec.test("ctx.stub auto-wraps _G.Osi and _G.Ext", function(ctx)
        -- Setup fake Osi/Ext globals for the context of this test
        local originalOsi = { 
            ApplyStatus = function() return "real status" end
        }
        _G.Osi = originalOsi

        ctx.TrackRestore(function()
            _G.Osi = nil
        end)

        local stub = ctx.stub(_G.Osi, "ApplyStatus", function()
            return "mock status"
        end)

        -- The wrapper mechanism replaces _G.Osi with a new object that inherits from original
        Assertions.NotEquals(_G.Osi, originalOsi, "_G.Osi should be replaced with a wrapper")
        Assertions.Equals(type(_G.Osi.ApplyStatus), "function", "ApplyStatus is present on wrapper")
        
        -- Calls through _G.Osi now hit the mock
        local result = _G.Osi.ApplyStatus()
        Assertions.Equals(result, "mock status", "mock implementation took effect")
        ctx.expect(stub).toHaveBeenCalledTimes(1)

        -- And the wrapper resolves fallback properly
        originalOsi.Untouched = function() return "real untouched" end
        Assertions.Equals(_G.Osi.Untouched(), "real untouched", "wrapper metatable inheritance")
    end)
end)
