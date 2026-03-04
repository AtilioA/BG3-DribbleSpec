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

DribbleSpec.describe("DribbleSpec Phase7 P7.3 toBeUuid", { tags = { "unit", "phase7", "expect", "entity" } }, function()
    DribbleSpec.test("toBeUuid accepts lowercase and uppercase UUID strings", function()
        DribbleSpec.expect("58a69333-40bf-8358-1d17-fff240d7fb12").toBeUuid()
        DribbleSpec.expect("58A69333-40BF-8358-1D17-FFF240D7FB12").toBeUuid()
    end)

    DribbleSpec.test("toBeUuid rejects non-uuid values", function()
        local errInvalidString = captureError(function()
            DribbleSpec.expect("not-a-uuid").toBeUuid()
        end)

        Assertions.Contains(errInvalidString, "toBeUuid", "matcher name")

        local errNonString = captureError(function()
            DribbleSpec.expect(123).toBeUuid()
        end)

        Assertions.Contains(errNonString, "toBeUuid", "non-string matcher name")
    end)
end)
