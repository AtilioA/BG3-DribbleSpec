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

DribbleSpec.describe("DribbleSpec Phase3 P3.1 expect toBe", { tags = { "unit", "phase3", "expect" } }, function()
    DribbleSpec.test("exposes DribbleSpec.expect and ctx.expect without global alias", function()
        Assertions.Equals(type(DribbleSpec.expect), "function", "DribbleSpec.expect type")
        Assertions.Equals(type(_G.expect), "nil", "global expect")

        local seenCtxExpectType = nil
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("expect context suite", function()
                dsl.test("ctx expect is callable", function(ctx)
                    seenCtxExpectType = type(ctx.expect)
                    ctx.expect(7).toBe(7)
                end)
            end)
        end)

        Assertions.Equals(seenCtxExpectType, "function", "ctx.expect type")
        Assertions.Equals(run.status, "passed", "run status")
    end)

    DribbleSpec.test("toBe passes on exact equality and fails with clear mismatch message", function()
        DribbleSpec.expect("alpha").toBe("alpha")

        local err = captureError(function()
            DribbleSpec.expect("alpha").toBe("beta")
        end)

        Assertions.Equals(type(err), "string", "toBe mismatch should throw")
        Assertions.Contains(err, "toBe", "matcher name")
        Assertions.Contains(err, "expected", "message includes expected")
        Assertions.Contains(err, "actual", "message includes actual")
    end)
end)
