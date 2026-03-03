local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase2 P2.2 tag filtering", { tags = { "unit", "phase2", "filter" } }, function()
    Dribble.test("requires all --tag values and omits non-matching tests", function()
        local trace = {}

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("runtime suite", { tags = { "runtime" } }, function()
                dsl.test("full match", { tags = { "fast", "client" } }, function()
                    table.insert(trace, "full")
                end)

                dsl.test("missing client", { tags = { "fast" } }, function()
                    table.insert(trace, "fast")
                end)

                dsl.test("missing fast", { tags = { "client" } }, function()
                    table.insert(trace, "client")
                end)
            end)
        end, {
            tags = { "runtime", "fast", "client" },
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 1, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
        Assertions.Equals(run.summary.total, 1, "total count")

        Assertions.Equals(table.concat(trace, "|"), "full", "executed tests")
        local suite = run.suites[1]
        Assertions.Equals(#suite.tests, 1, "selected tests count")
        Assertions.Equals(suite.tests[1].name, "full match", "selected test")
    end)
end)
