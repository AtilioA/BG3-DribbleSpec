-- Targets of the live recovery check: a mutation run over DirtyFixture.lua and DirtyVictimFixture.lua.
-- Mutant `false` to `true` in Close leaves the latch open, so the victims test fails until a reset.
local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
Ext.Require("Shared/DribbleSpec/Tests/Mutation/DirtyFixture.lua")
Ext.Require("Shared/DribbleSpec/Tests/Mutation/DirtyVictimFixture.lua")

-- The owner lets a mutation config select this suite alone (tools/mutation/recovery.config.json).
DribbleSpec.describe("DribbleSpec Mutation recovery fixture", {
    tags = { "mutation" },
    ownerModuleUUID = "95d8af72-eff9-40dc-9f9f-02effe3114fc",
}, function()
    DribbleSpec.test("Close closes the latch", function()
        Assertions.Equals(MutationDirtyFixture.open, false, "open before")
        MutationDirtyFixture.open = true
        MutationDirtyFixture.Close()
        Assertions.Equals(MutationDirtyFixture.open, false, "open")
    end)

    DribbleSpec.test("victims run with the latch closed", function()
        Assertions.Equals(MutationDirtyFixture.open, false, "open")
        Assertions.Equals(MutationDirtyVictimFixture.Double(2), 4, "Double(2)")
        Assertions.Equals(MutationDirtyVictimFixture.Same(3), 3, "Same(3)")
    end)
end)
