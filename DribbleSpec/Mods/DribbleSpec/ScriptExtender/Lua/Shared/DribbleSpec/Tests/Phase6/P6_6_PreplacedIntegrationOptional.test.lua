local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local SkipSignal = Ext.Require("Shared/DribbleSpec/Runtime/SkipSignal.lua")

local GUID_SHADOWHEART = "3ed74f06-3c60-42dc-83f6-f034cb47c679"

DribbleSpec.describe("DribbleSpec Phase6 P6.6 optional preplaced integration", {
    tags = { "phase6", "fixture", "integration", "entity" },
}, function()
    DribbleSpec.test("resolves a known preplaced entity when available", function(ctx)
        local probe = Ext.Entity.Get(GUID_SHADOWHEART)
        if probe == nil then
            SkipSignal.Throw("Optional integration skipped: known preplaced GUID not available in current runtime")
        end

        local handle = ctx.fixture.entity({
            provider = "preplaced",
            guid = GUID_SHADOWHEART,
        })

        Assertions.Equals(handle.value ~= nil, true, "resolved preplaced entity")
        Assertions.Equals(handle.guid, GUID_SHADOWHEART, "resolved guid")
        Assertions.Equals(handle.provider, "preplaced", "resolved provider")
    end)
end)
