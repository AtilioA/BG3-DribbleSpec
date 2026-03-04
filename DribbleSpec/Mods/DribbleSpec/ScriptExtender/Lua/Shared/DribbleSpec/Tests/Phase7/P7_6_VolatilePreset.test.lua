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

DribbleSpec.describe("DribbleSpec Phase7 P7.6 volatile preset", { tags = { "unit", "phase7", "expect", "entity" } },
    function()
        DribbleSpec.test("toEqual supports optional volatile preset filtering", function()
            local expected = {
                DisplayName = {
                    Name = "Shadowheart",
                },
                Handle = "Entity (deadbeef)",
                NetId = 10,
                ReplicationFlags = 1,
                RuntimeEntityId = 111,
            }

            local actual = {
                DisplayName = {
                    Name = "Shadowheart",
                },
                Handle = "Entity (cafebabe)",
                NetId = 900,
                ReplicationFlags = 255,
                RuntimeEntityId = 222,
            }

            DribbleSpec.expect(actual).toEqual(expected, {
                volatilePreset = "entity",
            })
        end)

        DribbleSpec.test("volatile filtering is opt-in and does not hide stable mismatches", function()
            local expected = {
                stable = {
                    hp = 42,
                },
                Handle = "Entity (a)",
            }

            local actual = {
                stable = {
                    hp = 21,
                },
                Handle = "Entity (b)",
            }

            local noPresetErr = captureError(function()
                DribbleSpec.expect(actual).toEqual(expected)
            end)
            Assertions.Contains(noPresetErr, "toEqual", "no preset mismatch")

            local stableMismatchErr = captureError(function()
                DribbleSpec.expect(actual).toEqual(expected, {
                    volatilePreset = "entity",
                })
            end)
            Assertions.Contains(stableMismatchErr, "toEqual", "stable mismatch still visible")
            Assertions.Contains(stableMismatchErr, "$.stable.hp", "stable mismatch path")
        end)

        DribbleSpec.test("unknown volatile preset fails with actionable error", function()
            local err = captureError(function()
                DribbleSpec.expect({}).toEqual({}, {
                    volatilePreset = "unknown",
                })
            end)

            Assertions.Contains(err, "toEqual", "matcher name")
            Assertions.Contains(err, "Unknown volatile preset", "unknown preset reason")
        end)
    end)
