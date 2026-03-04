local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local ConsoleIO = Ext.Require("Shared/DribbleSpec/Internal/ConsoleIO.lua")

Dribble.describe("DribbleSpec RunFromArgs integration", { tags = { "integration", "phase1" } }, function()
    Dribble.test("returns deterministic empty run for --help", function()
        local originalPrintHelp = ConsoleIO.PrintHelp
        local helpCalls = 0

        local ok, err = pcall(function()
            ConsoleIO.PrintHelp = function(_, topic)
                helpCalls = helpCalls + 1
                Assertions.Equals(topic, nil, "help topic")
            end

            local run = Dribble.RunFromArgs({ "dribble", "--help" })

            Assertions.Equals(run.status, "passed", "run status")
            Assertions.Equals(run.context, "unknown", "run context")
            Assertions.Equals(run.summary.total, 0, "summary total")
            Assertions.Equals(run.summary.passed, 0, "summary passed")
            Assertions.Equals(run.summary.failed, 0, "summary failed")
            Assertions.Equals(run.summary.skipped, 0, "summary skipped")
            Assertions.Equals(helpCalls, 1, "help call count")
        end)

        ConsoleIO.PrintHelp = originalPrintHelp
        if not ok then
            error(err)
        end
    end)

    Dribble.test("forwards optional help topic to ConsoleIO", function()
        local originalPrintHelp = ConsoleIO.PrintHelp
        local observedTopic = nil

        local ok, err = pcall(function()
            ConsoleIO.PrintHelp = function(_, topic)
                observedTopic = topic
            end

            local run = Dribble.RunFromArgs({ "dribble", "--help", "context" })
            Assertions.Equals(run.status, "passed", "run status")
            Assertions.Equals(observedTopic, "context", "forwarded topic")
        end)

        ConsoleIO.PrintHelp = originalPrintHelp
        if not ok then
            error(err)
        end
    end)
end)
