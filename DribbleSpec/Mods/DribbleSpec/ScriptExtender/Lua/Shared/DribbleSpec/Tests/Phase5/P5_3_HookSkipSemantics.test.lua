local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

DribbleSpec.describe("DribbleSpec Phase5 P5.3 hook skip semantics", { tags = { "unit", "phase5", "runtime" } }, function()
    DribbleSpec.test("context mismatch in beforeAll skips remaining suite tests", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("beforeAll requireClient suite", function()
                dsl.beforeAll(function(ctx)
                    ctx.requireClient()
                end)

                dsl.test("first", function() end)
                dsl.test("second", function() end)
            end)
        end, {
            context = "server",
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 0, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 2, "skipped count")
        Assertions.Contains(run.suites[1].tests[1].skipReason, "client context", "beforeAll skip reason")
    end)

    DribbleSpec.test("context mismatch in beforeEach skips current test only", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("beforeEach requireClient suite", function()
                dsl.beforeEach(function(ctx)
                    ctx.requireClient()
                end)

                dsl.test("first", function() end)
                dsl.test("second", function() end)
            end)
        end, {
            context = "server",
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 0, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 2, "skipped count")
        Assertions.Contains(run.suites[1].tests[1].skipReason, "client context", "beforeEach first skip reason")
        Assertions.Contains(run.suites[1].tests[2].skipReason, "client context", "beforeEach second skip reason")
    end)
end)
