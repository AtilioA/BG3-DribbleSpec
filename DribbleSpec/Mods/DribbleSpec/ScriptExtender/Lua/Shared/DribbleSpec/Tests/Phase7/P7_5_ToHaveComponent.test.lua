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

DribbleSpec.describe("DribbleSpec Phase7 P7.5 toHaveComponent", { tags = { "unit", "phase7", "expect", "entity" } },
    function()
        DribbleSpec.test("toHaveComponent passes when component exists", function()
            local entityLike = {
                GetComponent = function(_, componentName)
                    if componentName == "DisplayName" then
                        return {
                            Name = "Astarion",
                        }
                    end

                    return nil
                end,
            }

            DribbleSpec.expect(entityLike).toHaveComponent("DisplayName")
        end)

        DribbleSpec.test("toHaveComponent works with EntityRef inputs", function()
            local ref = DribbleSpec.entityRef(function()
                return {
                    GetComponent = function(_, componentName)
                        if componentName == "Stats" then
                            return {
                                Level = 3,
                            }
                        end

                        return nil
                    end,
                }
            end)

            DribbleSpec.expect(ref).toHaveComponent("Stats")
        end)

        DribbleSpec.test("toHaveComponent fails with clear matcher errors", function()
            local missingComponentErr = captureError(function()
                DribbleSpec.expect({
                    GetComponent = function()
                        return nil
                    end,
                }).toHaveComponent("DisplayName")
            end)

            Assertions.Contains(missingComponentErr, "toHaveComponent", "matcher name")
            Assertions.Contains(missingComponentErr, "DisplayName", "missing component name")

            local invalidNameErr = captureError(function()
                DribbleSpec.expect({
                    GetComponent = function()
                        return {
                            Name = "any",
                        }
                    end,
                }).toHaveComponent(42)
            end)

            Assertions.Contains(invalidNameErr, "toHaveComponent", "invalid name matcher")
        end)
    end)
