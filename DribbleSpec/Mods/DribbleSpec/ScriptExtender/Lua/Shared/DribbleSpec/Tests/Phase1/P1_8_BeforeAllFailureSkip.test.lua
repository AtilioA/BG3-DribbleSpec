local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase1 P1.8 beforeAll failure", function()
    Dribble.test("marks remaining suite tests as skipped when beforeAll fails", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("beforeAll failure suite", function()
                dsl.beforeAll(function()
                    error("p1.8 beforeAll failure")
                end)

                dsl.test("skipped test A", function()
                    error("should not execute")
                end)

                dsl.test("skipped test B", function()
                    error("should not execute")
                end)
            end)
        end)

        Assertions.Equals(run.status, "failed", "run status")
        Assertions.Equals(run.summary.failed, 1, "failed count")
        Assertions.Equals(run.summary.skipped, 2, "skipped count")
        Assertions.Equals(run.summary.passed, 0, "passed count")
        Assertions.Equals(run.summary.total, 3, "total count")

        local suite = run.suites[1]
        Assertions.Equals(suite.tests[1].name, "[hook] beforeAll", "hook record name")
        Assertions.Equals(suite.tests[1].status, "failed", "hook record status")
        Assertions.Contains(suite.tests[1].error.message, "p1.8 beforeAll failure", "hook failure message")

        Assertions.Equals(suite.tests[2].status, "skipped", "first skipped test status")
        Assertions.Equals(suite.tests[3].status, "skipped", "second skipped test status")
        Assertions.Equals(suite.tests[2].skipReason, "Suite beforeAll failed", "first skipped reason")
        Assertions.Equals(suite.tests[3].skipReason, "Suite beforeAll failed", "second skipped reason")
    end)
end)
