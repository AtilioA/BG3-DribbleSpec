local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local Registry = Ext.Require("Shared/DribbleSpec/Core/Registry.lua")
local ResultModel = Ext.Require("Shared/DribbleSpec/Core/ResultModel.lua")
local Runner = Ext.Require("Shared/DribbleSpec/Runner/Runner.lua")
local Options = Ext.Require("Shared/DribbleSpec/Runner/Options.lua")
local Clock = Ext.Require("Shared/DribbleSpec/Internal/Clock.lua")
local RunService = Ext.Require("Shared/DribbleSpec/Runtime/RunService.lua")

---@return table
local function createRunServiceWithRegistry(registry)
    return RunService.Create({
        registry = registry,
        options = Options,
        clock = Clock,
        runner = Runner,
        resultModel = ResultModel,
    })
end

DribbleSpec.describe("DribbleSpec RunService warnings", { tags = { "unit", "phase1", "runtime" } }, function()
    DribbleSpec.test("adds warning when registry has no suites", function()
        local registry = Registry.Create()
        local service = createRunServiceWithRegistry(registry)

        local run = service.Run({})
        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.total, 0, "summary total")
        Assertions.Equals(#run.warnings, 1, "warning count")
        Assertions.Contains(run.warnings[1], "No tests registered", "warning text")
    end)

    DribbleSpec.test("does not add empty-registry warning when suites exist", function()
        local registry = Registry.Create()
        registry:BeginSuite("RunService warning sample", nil)
        registry:AddTest("executes", nil, function()
        end)
        registry:EndSuite()

        local service = createRunServiceWithRegistry(registry)
        local run = service.Run({})

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.total, 1, "summary total")
        Assertions.Equals(#run.warnings, 0, "warning count")
    end)
end)
