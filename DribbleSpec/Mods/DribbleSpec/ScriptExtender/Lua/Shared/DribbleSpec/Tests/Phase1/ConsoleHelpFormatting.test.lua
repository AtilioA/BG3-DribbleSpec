local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local ConsoleIO = Ext.Require("Shared/DribbleSpec/Internal/ConsoleIO.lua")

Dribble.describe("DribbleSpec console help formatting", { tags = { "unit", "phase1", "cli" } }, function()
    Dribble.test("prints organized overview sections and examples", function()
        local lines = {}
        ConsoleIO.PrintHelp(function(message)
            table.insert(lines, message)
        end)

        local output = table.concat(lines, "\n")
        Assertions.Contains(output, "Usage:", "usage heading")
        Assertions.Contains(output, "dribble [options]", "short usage line")
        Assertions.Contains(output, "dribble --help [topic]", "topic usage line")
        Assertions.Contains(output, "Options:", "options heading")
        Assertions.Contains(output, "--tag <tag>", "tag option")
        Assertions.Contains(output, "--context <client|server|any>", "context option")
        Assertions.Contains(output, "Examples:", "examples heading")
        Assertions.Contains(output, "dribble --help tag", "tag example")
    end)

    Dribble.test("prints topic help for tag and context", function()
        local tagLines = {}
        ConsoleIO.PrintHelp(function(message)
            table.insert(tagLines, message)
        end, "tag")

        local tagOutput = table.concat(tagLines, "\n")
        Assertions.Contains(tagOutput, "Topic: tag", "tag topic heading")
        Assertions.Contains(tagOutput, "repeatable", "tag repeatable detail")
        Assertions.Contains(tagOutput, "--tag runtime --tag server", "tag example")

        local contextLines = {}
        ConsoleIO.PrintHelp(function(message)
            table.insert(contextLines, message)
        end, "context")

        local contextOutput = table.concat(contextLines, "\n")
        Assertions.Contains(contextOutput, "Topic: context", "context topic heading")
        Assertions.Contains(contextOutput, "client", "context client detail")
        Assertions.Contains(contextOutput, "server", "context server detail")
    end)

    Dribble.test("prints unknown topic guidance with available topics", function()
        local lines = {}
        ConsoleIO.PrintHelp(function(message)
            table.insert(lines, message)
        end, "nope")

        local output = table.concat(lines, "\n")
        Assertions.Contains(output, "Unknown help topic", "unknown topic warning")
        Assertions.Contains(output, "Available topics:", "available topics heading")
        Assertions.Contains(output, "tag", "tag topic listed")
        Assertions.Contains(output, "context", "context topic listed")
    end)
end)
