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

DribbleSpec.describe("DribbleSpec Phase3 P3.2 core matchers", { tags = { "unit", "phase3", "expect" } }, function()
    DribbleSpec.test("supports toBeNil, toBeTruthy, and toBeFalsy", function()
        DribbleSpec.expect(nil).toBeNil()
        DribbleSpec.expect("hello").toBeTruthy()
        DribbleSpec.expect(false).toBeFalsy()

        local nilErr = captureError(function()
            DribbleSpec.expect(1).toBeNil()
        end)
        Assertions.Contains(nilErr, "toBeNil", "toBeNil matcher label")

        local truthyErr = captureError(function()
            DribbleSpec.expect(false).toBeTruthy()
        end)
        Assertions.Contains(truthyErr, "toBeTruthy", "toBeTruthy matcher label")

        local falsyErr = captureError(function()
            DribbleSpec.expect("x").toBeFalsy()
        end)
        Assertions.Contains(falsyErr, "toBeFalsy", "toBeFalsy matcher label")
    end)

    DribbleSpec.test("supports toContain for strings and array tables", function()
        DribbleSpec.expect("alpha beta gamma").toContain("beta")
        DribbleSpec.expect({ "a", "b", "c" }).toContain("b")

        local stringErr = captureError(function()
            DribbleSpec.expect("alpha beta gamma").toContain("delta")
        end)
        Assertions.Contains(stringErr, "toContain", "string toContain matcher label")

        local tableErr = captureError(function()
            DribbleSpec.expect({ 1, 2, 3 }).toContain(9)
        end)
        Assertions.Contains(tableErr, "toContain", "table toContain matcher label")
    end)

    DribbleSpec.test("supports toThrow and toThrowMatch with Lua patterns", function()
        DribbleSpec.expect(function()
            error("boom 42")
        end).toThrow()

        DribbleSpec.expect(function()
            error("boom 42")
        end).toThrowMatch("boom%s+%d+")

        local throwErr = captureError(function()
            DribbleSpec.expect(function()
                return 1
            end).toThrow()
        end)
        Assertions.Contains(throwErr, "toThrow", "toThrow matcher label")

        local throwMatchErr = captureError(function()
            DribbleSpec.expect(function()
                error("different message")
            end).toThrowMatch("boom%s+%d+")
        end)
        Assertions.Contains(throwMatchErr, "toThrowMatch", "toThrowMatch matcher label")
    end)
end)
