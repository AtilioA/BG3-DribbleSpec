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

DribbleSpec.describe("DribbleSpec Phase7 P7.4 toBeEntity", { tags = { "unit", "phase7", "expect", "entity" } }, function()
    DribbleSpec.test("toBeEntity accepts entity-like values", function()
        local entityLike = {
            GetComponent = function(_, componentName)
                if componentName == "DisplayName" then
                    return {
                        Name = "Karlach",
                    }
                end

                return nil
            end,
        }

        DribbleSpec.expect(entityLike).toBeEntity()
    end)

    DribbleSpec.test("toBeEntity accepts resolvable EntityRef", function()
        local ref = DribbleSpec.entityRef(function()
            return {
                GetComponent = function(_, componentName)
                    if componentName == "DisplayName" then
                        return {
                            Name = "Wyll",
                        }
                    end

                    return nil
                end,
            }
        end)

        DribbleSpec.expect(ref).toBeEntity()
    end)

    DribbleSpec.test("toBeEntity fails for unresolved or non-entity values", function()
        local unresolvedRef = DribbleSpec.entityRef(function()
            return nil
        end)

        local unresolvedErr = captureError(function()
            DribbleSpec.expect(unresolvedRef).toBeEntity()
        end)

        Assertions.Contains(unresolvedErr, "toBeEntity", "matcher name")
        Assertions.Contains(unresolvedErr, "could not be resolved", "unresolved ref reason")

        local nonEntityErr = captureError(function()
            DribbleSpec.expect({ value = "not entity" }).toBeEntity()
        end)

        Assertions.Contains(nonEntityErr, "toBeEntity", "non-entity matcher name")
    end)
end)
