local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

Dribble.describe("DribbleSpec Phase7 P7.1 entityRef basics", { tags = { "unit", "phase7", "entity" } }, function()
    Dribble.test("Dribble.entityRef resolves lazily from resolver", function()
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

        local ref = Dribble.entityRef(function()
            return currentEntity
        end)

        Dribble.expect(ref).toBeEntity()

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

    Dribble.test("Dribble.entityRef keeps GUID identity", function()
        local guid = "58a69333-40bf-8358-1d17-fff240d7fb12"
        local ref = Dribble.entityRef(guid)

        Assertions.Equals(ref:GetGuid(), guid, "stored guid")
    end)
end)
