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

Dribble.describe("DribbleSpec Phase7 P7.3 toBeGuid", { tags = { "unit", "phase7", "expect", "entity" } }, function()
    Dribble.test("toBeGuid accepts lowercase and uppercase GUID strings", function()
        Dribble.expect("58a69333-40bf-8358-1d17-fff240d7fb12").toBeGuid()
        Dribble.expect("58A69333-40BF-8358-1D17-FFF240D7FB12").toBeGuid()
    end)

    Dribble.test("toBeGuid rejects non-guid values", function()
        local errInvalidString = captureError(function()
            Dribble.expect("not-a-guid").toBeGuid()
        end)

        Assertions.Contains(errInvalidString, "toBeGuid", "matcher name")

        local errNonString = captureError(function()
            Dribble.expect(123).toBeGuid()
        end)

        Assertions.Contains(errNonString, "toBeGuid", "non-string matcher name")
    end)
end)
