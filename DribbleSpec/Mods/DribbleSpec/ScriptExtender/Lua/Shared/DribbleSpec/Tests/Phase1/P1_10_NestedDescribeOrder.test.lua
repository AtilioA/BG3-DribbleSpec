local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase1 P1.10 nested describe", function()
    Dribble.test("preserves nested full names and hook execution order", function()
        local trace = {}

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("root", function()
                dsl.beforeEach(function()
                    table.insert(trace, "root beforeEach")
                end)

                dsl.afterEach(function()
                    table.insert(trace, "root afterEach")
                end)

                dsl.describe("child", function()
                    dsl.beforeEach(function()
                        table.insert(trace, "child beforeEach")
                    end)

                    dsl.afterEach(function()
                        table.insert(trace, "child afterEach")
                    end)

                    dsl.test("nested test", function()
                        table.insert(trace, "nested test")
                    end)
                end)
            end)
        end)

        Assertions.Equals(run.status, "passed", "run status")
        Assertions.Equals(run.summary.passed, 1, "passed count")
        Assertions.Equals(run.summary.total, 1, "total count")

        local rootSuite = run.suites[1]
        local childSuite = rootSuite.suites[1]
        local nestedResult = childSuite.tests[1]

        Assertions.Equals(rootSuite.name, "root", "root suite name")
        Assertions.Equals(childSuite.name, "root child", "child suite full name")
        Assertions.Equals(nestedResult.fullName, "root child nested test", "nested test full name")

        Assertions.Equals(table.concat(trace, " | "),
            "root beforeEach | child beforeEach | nested test | child afterEach | root afterEach",
            "nested hook execution order")
    end)
end)
