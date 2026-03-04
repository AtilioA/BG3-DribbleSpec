local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

DribbleSpec.describe("DribbleSpec Phase7 P7.1 entityRef basics", { tags = { "unit", "phase7", "entity" } }, function()
    DribbleSpec.test("DribbleSpec.entityRef resolves lazily from resolver", function()
        local currentEntity = {
            GetComponent = function(_, componentName)
                if componentName == "DisplayName" then
                    return {
                        Name = "first",
                    }
                end

                return nil
            end,
        }

        local ref = DribbleSpec.entityRef(function()
            return currentEntity
        end)

        DribbleSpec.expect(ref).toBeEntity()

        currentEntity = {
            GetComponent = function(_, componentName)
                if componentName == "DisplayName" then
                    return {
                        Name = "second",
                    }
                end

                return nil
            end,
        }

        local resolved = ref:Resolve()
        local displayName = resolved:GetComponent("DisplayName")
        Assertions.Equals(displayName.Name, "second", "lazy re-resolution")
    end)

    DribbleSpec.test("DribbleSpec.entityRef keeps GUID identity", function()
        local guid = "58a69333-40bf-8358-1d17-fff240d7fb12"
        local ref = DribbleSpec.entityRef(guid)

        Assertions.Equals(ref:GetGuid(), guid, "stored guid")
    end)
end)
