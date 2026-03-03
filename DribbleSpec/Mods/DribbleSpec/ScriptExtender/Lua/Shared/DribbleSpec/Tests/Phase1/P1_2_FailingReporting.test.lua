local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase1 P1.2 failing reporting", { tags = { "unit", "phase1" } }, function()
    Dribble.test("captures failed test error message and stack", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("P1.2 inner suite", function()
                dsl.test("fails intentionally", function()
                    error("p1.2 intentional failure")
                end)
            end)
        end)

        Assertions.Equals(run.status, "failed", "run status")
        Assertions.Equals(run.summary.failed, 1, "failed count")
        Assertions.Equals(run.summary.passed, 0, "passed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
        Assertions.Equals(run.summary.total, 1, "total count")

        local suite = run.suites[1]
        local testResult = suite.tests[1]
        Assertions.Equals(testResult.status, "failed", "test status")
        Assertions.Contains(testResult.error.message, "p1.2 intentional failure", "error message")
        Assertions.Contains(testResult.error.stack, "p1.2 intentional failure", "error stack")
    end)
end)
