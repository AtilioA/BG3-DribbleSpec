local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

DribbleSpec.describe("DribbleSpec Phase2 P2.3 context filtering", { tags = { "unit", "phase2", "filter" } }, function()
    DribbleSpec.test("includes untagged plus client-tagged tests for --context client", function()
        local trace = {}

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("context suite", function()
                dsl.test("untagged", function()
                    table.insert(trace, "untagged")
                end)

                dsl.test("client tagged", { tags = { "client" } }, function()
                    table.insert(trace, "client")
                end)

                dsl.test("server tagged", { tags = { "server" } }, function()
                    table.insert(trace, "server")
                end)
            end)
        end, {
            context = "client",
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 2, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
        Assertions.Equals(run.summary.total, 2, "total count")
        Assertions.Equals(table.concat(trace, "|"), "untagged|client", "executed tests")

        local suite = run.suites[1]
        Assertions.Equals(#suite.tests, 2, "selected tests count")
    end)

    DribbleSpec.test("includes untagged plus server-tagged tests for --context server", function()
        local trace = {}

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("context suite", function()
                dsl.test("untagged", function()
                    table.insert(trace, "untagged")
                end)

                dsl.test("client tagged", { tags = { "client" } }, function()
                    table.insert(trace, "client")
                end)

                dsl.test("server tagged", { tags = { "server" } }, function()
                    table.insert(trace, "server")
                end)
            end)
        end, {
            context = "server",
        })

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 2, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
        Assertions.Equals(run.summary.skipped, 0, "skipped count")
        Assertions.Equals(run.summary.total, 2, "total count")
        Assertions.Equals(table.concat(trace, "|"), "untagged|server", "executed tests")

        local suite = run.suites[1]
        Assertions.Equals(#suite.tests, 2, "selected tests count")
    end)
end)
