local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase2 P2.4 fail-fast", { tags = { "unit", "phase2", "runner" } }, function()
    Dribble.test("stops after first failed test when --fail-fast is enabled", function()
        local trace = {}

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("fail fast suite", function()
                dsl.test("first fails", function()
                    table.insert(trace, "first")
                    error("intentional failure")
                end)

                dsl.test("second should not run", function()
                    table.insert(trace, "second")
                end)
            end)
        end, {
            failFast = true,
        })

        Assertions.Equals(run.status, "failed", "run status")
        Assertions.Equals(run.summary.passed, 0, "passed count")
        Assertions.Equals(run.summary.failed, 1, "failed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
        Assertions.Equals(run.summary.total, 1, "total count")
        Assertions.Equals(table.concat(trace, "|"), "first", "executed tests")

        local suite = run.suites[1]
        Assertions.Equals(#suite.tests, 1, "recorded tests count")
        Assertions.Equals(suite.tests[1].name, "first fails", "recorded test")
    end)

    Dribble.test("stops entire run after beforeAll failure when --fail-fast is enabled", function()
        local trace = {}

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("failing setup suite", function()
                dsl.beforeAll(function()
                    error("setup exploded")
                end)

                dsl.test("test in failing suite", function()
                    table.insert(trace, "failing suite test")
                end)
            end)

            dsl.describe("second suite", function()
                dsl.test("should not run", function()
                    table.insert(trace, "second suite test")
                end)
            end)
        end, {
            failFast = true,
        })

        Assertions.Equals(run.status, "failed", "run status")
        Assertions.Equals(run.summary.passed, 0, "passed count")
        Assertions.Equals(run.summary.failed, 1, "failed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
        Assertions.Equals(run.summary.total, 1, "total count")
        Assertions.Equals(table.concat(trace, "|"), "", "executed tests")
        Assertions.Equals(#run.suites, 1, "suite count")

        local suite = run.suites[1]
        Assertions.Equals(suite.tests[1].name, "[hook] beforeAll", "recorded failure")
    end)
end)
