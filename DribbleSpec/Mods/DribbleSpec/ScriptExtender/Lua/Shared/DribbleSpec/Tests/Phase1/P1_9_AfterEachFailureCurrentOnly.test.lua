local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase1 P1.9 afterEach failure", function()
    Dribble.test("fails current test only and continues with later tests", function()
        local afterEachCalls = 0
        local secondTestRan = false

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("afterEach failure suite", function()
                dsl.afterEach(function()
                    afterEachCalls = afterEachCalls + 1
                    if afterEachCalls == 1 then
                        error("p1.9 afterEach failure on first test")
                    end
                end)

                dsl.test("test A", function()
                end)

                dsl.test("test B", function()
                    secondTestRan = true
                end)
            end)
        end)

        Assertions.Equals(secondTestRan, true, "second test execution")
        Assertions.Equals(afterEachCalls, 2, "afterEach call count")
        Assertions.Equals(run.status, "failed", "run status")
        Assertions.Equals(run.summary.failed, 1, "failed count")
        Assertions.Equals(run.summary.passed, 1, "passed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
        Assertions.Equals(run.summary.total, 2, "total count")

        local suite = run.suites[1]
        Assertions.Equals(suite.tests[1].status, "failed", "first test status")
        Assertions.Contains(suite.tests[1].error.message, "p1.9 afterEach failure on first test", "first test error")
        Assertions.Equals(suite.tests[2].status, "passed", "second test status")
    end)
end)
