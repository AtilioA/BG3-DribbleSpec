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

DribbleSpec.describe("DribbleSpec Phase3 P3.3 toEqual diff", { tags = { "unit", "phase3", "expect" } }, function()
    DribbleSpec.test("toEqual passes for deep table equality with stable key ordering", function()
        local expected = {
            name = "Astarion",
            stats = {
                hp = 35,
                ap = 2,
            },
            tags = { "rogue", "spawn" },
        }

        local actual = {
            tags = { "rogue", "spawn" },
            stats = {
                ap = 2,
                hp = 35,
            },
            name = "Astarion",
        }

        DribbleSpec.expect(actual).toEqual(expected)
    end)

    DribbleSpec.test("toEqual includes mismatch path and values when comparison fails", function()
        local expected = {
            stats = {
                hp = 35,
                ap = 2,
            },
        }

        local actual = {
            stats = {
                hp = 33,
                ap = 2,
            },
        }

        local err = captureError(function()
            DribbleSpec.expect(actual).toEqual(expected)
        end)

        Assertions.Equals(type(err), "string", "toEqual mismatch should throw")
        Assertions.Contains(err, "toEqual", "matcher name")
        Assertions.Contains(err, "$.stats.hp", "mismatch path")
        Assertions.Contains(err, "expected=35", "expected value")
        Assertions.Contains(err, "actual=33", "actual value")
    end)

    DribbleSpec.test("toEqual handles self-referential tables safely", function()
        local expected = {
            name = "loop",
        }
        expected.self = expected

        local actual = {
            name = "loop",
        }
        actual.self = actual

        DribbleSpec.expect(actual).toEqual(expected)
    end)
end)
