local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local ExecutionRouter = Ext.Require("Shared/DribbleSpec/Runtime/ExecutionRouter.lua")

Dribble.describe("DribbleSpec ExecutionRouter server targeting", { tags = { "unit", "phase1" } }, function()
    Dribble.test("routes client --context server through remote request", function()
        local localRuns = 0
        local remoteRuns = 0
        local rendered = {}
        local lines = {}
        local warnings = {}

        local result = ExecutionRouter.Run({ context = "server" }, {
            isClient = function()
                return true
            end,
            requestServerRun = function(_, onReply)
                remoteRuns = remoteRuns + 1
                onReply({
                    runResult = {
                        summary = { passed = 1, failed = 0, skipped = 0, total = 1 },
                        suites = {},
                    },
                })
            end,
            runLocal = function()
                localRuns = localRuns + 1
                return {}
            end,
            renderRun = function(run)
                table.insert(rendered, run)
            end,
            buildPendingRun = function()
                return { pending = true }
            end,
            printLine = function(message)
                table.insert(lines, message)
            end,
            printWarning = function(message)
                table.insert(warnings, message)
            end,
        })

        Assertions.Equals(localRuns, 0, "local run count")
        Assertions.Equals(remoteRuns, 1, "remote run count")
        Assertions.Equals(result.pending, true, "pending result returned")
        Assertions.Equals(#rendered, 1, "remote render count")
        Assertions.Equals(#warnings, 0, "warning count")
        Assertions.Contains(lines[1], "Requested server-context run", "info line")
    end)

    Dribble.test("runs local when server targeting is not requested", function()
        local localRuns = 0
        local remoteRuns = 0
        local rendered = {}

        local result = ExecutionRouter.Run({ context = "any" }, {
            isClient = function()
                return true
            end,
            requestServerRun = function(_, _)
                remoteRuns = remoteRuns + 1
            end,
            runLocal = function()
                localRuns = localRuns + 1
                return { done = true }
            end,
            renderRun = function(run)
                table.insert(rendered, run)
            end,
            buildPendingRun = function()
                return {}
            end,
            printLine = function(_)
            end,
            printWarning = function(_)
            end,
        })

        Assertions.Equals(localRuns, 1, "local run count")
        Assertions.Equals(remoteRuns, 0, "remote run count")
        Assertions.Equals(#rendered, 1, "render count")
        Assertions.Equals(result.done, true, "local run result")
    end)
end)
