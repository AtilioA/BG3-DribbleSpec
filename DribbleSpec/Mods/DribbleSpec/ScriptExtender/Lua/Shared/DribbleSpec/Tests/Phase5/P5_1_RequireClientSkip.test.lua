local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

DribbleSpec.describe("DribbleSpec Phase5 P5.1 requireClient skip", { tags = { "unit", "phase5", "runtime" } }, function()
    DribbleSpec.test("ctx.requireClient marks mismatch as skipped", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("requireClient suite", function()
                dsl.test("client-only test", function(ctx)
                    ctx.requireClient()
                end)
            end)
        end, {
            context = "server",
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 0, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 1, "skipped count")
        Assertions.Equals(run.summary.total, 1, "total count")
        Assertions.Contains(run.suites[1].tests[1].skipReason, "client context", "skip reason")
    end)
end)
