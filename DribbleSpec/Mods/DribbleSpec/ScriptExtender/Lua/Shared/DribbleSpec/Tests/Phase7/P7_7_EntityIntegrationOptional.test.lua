local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local SkipSignal = Ext.Require("Shared/DribbleSpec/Runtime/SkipSignal.lua")

local GUID_SHADOWHEART = "3ed74f06-3c60-42dc-83f6-f034cb47c679"

DribbleSpec.describe("DribbleSpec Phase7 P7.7 optional entity integration", {
    tags = { "phase7", "integration", "entity", "server" },
}, function()
    DribbleSpec.test("entity domain matchers work with a known preplaced entity when available", function(ctx)
        ctx.requireServer()

        local probe = Ext.Entity.Get(GUID_SHADOWHEART)
        if probe == nil then
            SkipSignal.Throw("Optional integration skipped: known preplaced GUID not available in current runtime")
        end

        ctx.expect(GUID_SHADOWHEART).toBeUuid()
        ctx.expect(probe).toBeEntity()
        ctx.expect(probe).toHaveComponent("DisplayName")

        local ref = ctx.entityRef(GUID_SHADOWHEART)
        ctx.expect(ref).toBeEntity()
        ctx.expect(ref).toHaveComponent("DisplayName")
    end)
end)
