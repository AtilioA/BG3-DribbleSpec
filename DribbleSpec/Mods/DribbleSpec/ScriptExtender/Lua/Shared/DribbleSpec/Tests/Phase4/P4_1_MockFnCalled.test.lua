local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

---@param fn function
---@return string|nil
local function captureError(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        return nil
    end

    return tostring(err)
end

DribbleSpec.describe("DribbleSpec Phase4 P4.1 mockFn called", { tags = { "unit", "phase4", "doubles" } }, function()
    DribbleSpec.test("ctx.mockFn returns callable spy and toHaveBeenCalled reflects invocation", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("phase4 mockFn suite", function()
                dsl.test("mockFn baseline", function(ctx)
                    local spy = ctx.mockFn()
                    Assertions.Equals(type(spy), "function", "mockFn result type")

                    local beforeErr = captureError(function()
                        ctx.expect(spy).toHaveBeenCalled()
                    end)
                    Assertions.Equals(type(beforeErr), "string", "toHaveBeenCalled before call")

                    spy("alpha")
                    ctx.expect(spy).toHaveBeenCalled()
                end)
            end)
        end)

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 1, "passed count")
    end)
end)
