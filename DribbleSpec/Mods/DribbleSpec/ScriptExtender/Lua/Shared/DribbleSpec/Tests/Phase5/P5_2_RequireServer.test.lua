local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

DribbleSpec.describe("DribbleSpec Phase5 P5.2 requireServer", { tags = { "unit", "phase5", "runtime" } }, function()
    DribbleSpec.test("ctx.requireServer allows matching server context", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("requireServer suite", function()
                dsl.test("server-only test", function(ctx)
                    ctx.requireServer()
                end)
            end)
        end, {
            context = "server",
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 1, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
    end)

    DribbleSpec.test("ctx.requireServer marks mismatch as skipped", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("requireServer mismatch suite", function()
                dsl.test("server-only test", function(ctx)
                    ctx.requireServer()
                end)
            end)
        end, {
            context = "client",
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 0, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 1, "skipped count")
        Assertions.Contains(run.suites[1].tests[1].skipReason, "server context", "skip reason")
    end)
end)
