local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase2 P2.1 name filtering", { tags = { "unit", "phase2", "filter" } }, function()
    Dribble.test("matches fullName by plain substring, case-insensitive", function()
        local trace = {}

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("Alpha Suite", function()
                dsl.test("First Case", function()
                    table.insert(trace, "first")
                end)

                dsl.test("Second Needle", function()
                    table.insert(trace, "second")
                end)
            end)

            dsl.describe("Beta Suite", function()
                dsl.test("Never selected", function()
                    table.insert(trace, "beta")
                end)
            end)
        end, {
            namePattern = "sUiTe SeCoNd",
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 1, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
        Assertions.Equals(run.summary.total, 1, "total count")

        Assertions.Equals(table.concat(trace, "|"), "second", "executed tests")
        Assertions.Equals(#run.suites, 1, "selected suite count")
        local suite = run.suites[1]
        Assertions.Equals(#suite.tests, 1, "selected tests count")
        Assertions.Equals(suite.tests[1].fullName, "Alpha Suite Second Needle", "selected fullName")
    end)
end)
