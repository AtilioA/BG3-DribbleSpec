local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")
local ConsoleReporter = Ext.Require("Shared/DribbleSpec/Reporters/ConsoleReporter.lua")

Dribble.describe("DribbleSpec Console Reporter Formatting", function()
    Dribble.test("shows colored squares and all test outcomes", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("Reporter demo suite", function()
                dsl.test("pass case", function()
                end)

                dsl.test.skip("skip case", function()
                    error("skip body should not execute")
                end)

                dsl.test("fail case", function()
                    error("console reporter failure")
                end)
            end)
        end)

        local output = table.concat(ConsoleReporter.BuildLines(run), "\n")
        Assertions.Contains(output, "pass case", "includes passed test")
        Assertions.Contains(output, "skip case", "includes skipped test")
        Assertions.Contains(output, "fail case", "includes failed test")
        Assertions.Contains(output, "\x1b[38;2;21;255;81m■", "green square present")
        Assertions.Contains(output, "\x1b[38;2;255;10;40m■", "red square present")
        Assertions.Contains(output, "\x1b[38;2;255;214;10m■", "yellow square present")
        Assertions.Contains(output, "console reporter failure", "includes failure message")
        Assertions.Contains(output, "RESULTS", "uppercase results heading")
        Assertions.Contains(output, "SUMMARY", "uppercase summary heading")
        Assertions.Contains(output, "Passed (1):", "passed count format")
        Assertions.Contains(output, "Failed (1):", "failed count format")
        Assertions.Contains(output, "Skipped (1):", "skipped count format")
    end)

    Dribble.test("omits zero-count suite metrics", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("Only pass suite", function()
                dsl.test("pass case", function()
                end)
            end)
        end)

        local output = table.concat(ConsoleReporter.BuildLines(run), "\n")
        local suiteLine = string.match(output, "[^\n]*Suite:[^\n]*")
        Assertions.Contains(suiteLine, "\x1b[38;2;21;255;81m■", "suite has pass metric")
        Assertions.NotContains(suiteLine, "\x1b[38;2;255;10;40m■", "suite omits failed metric")
        Assertions.NotContains(suiteLine, "\x1b[38;2;255;214;10m■", "suite omits skipped metric")
    end)

    Dribble.test("routes warnings through warning sink", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("Reporter warning suite", function()
                dsl.test("pass case", function()
                end)
            end)
        end)
        run.warnings = { "first warning", "second warning" }

        local lines = {}
        local warningLines = {}
        ConsoleReporter.PrintRun(run, {
            printLine = function(message)
                table.insert(lines, message)
            end,
            printWarning = function(message)
                table.insert(warningLines, message)
            end,
        })

        Assertions.Equals(#lines > 0, true, "report produced lines")
        Assertions.Equals(#warningLines, 2, "warning line count")
        Assertions.Contains(warningLines[1], "first warning", "first warning content")
        Assertions.Contains(warningLines[2], "second warning", "second warning content")
    end)
end)
