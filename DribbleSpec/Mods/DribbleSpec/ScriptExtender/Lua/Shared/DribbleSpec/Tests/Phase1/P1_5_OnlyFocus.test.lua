local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

DribbleSpec.describe("DribbleSpec Phase1 P1.5 test.only focus", { tags = { "unit", "phase1" } }, function()
    DribbleSpec.test("runs only focused tests and skips the rest", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("focus suite", function()
                dsl.test("non focused A", function()
                    error("non focused test should be skipped")
                end)

                dsl.test.only("focused", function()
                end)

                dsl.test("non focused B", function()
                    error("non focused test should be skipped")
                end)
            end)

            dsl.describe("unfocused suite", function()
                dsl.test("non focused C", function()
                    error("suite without only should be skipped")
                end)
            end)
        end)

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 1, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 3, "skipped count")
        Assertions.Equals(run.summary.total, 4, "total count")

        local focusSuite = run.suites[1]
        Assertions.Equals(focusSuite.tests[1].status, "skipped", "non focused A status")
        Assertions.Equals(focusSuite.tests[2].status, "passed", "focused status")
        Assertions.Equals(focusSuite.tests[3].status, "skipped", "non focused B status")
        Assertions.Equals(focusSuite.tests[1].skipReason, "Excluded by test.only focus", "non focused A reason")

        local otherSuite = run.suites[2]
        Assertions.Equals(otherSuite.tests[1].status, "skipped", "unfocused suite status")
        Assertions.Equals(otherSuite.tests[1].skipReason, "Excluded by test.only focus", "unfocused suite reason")
    end)
end)
