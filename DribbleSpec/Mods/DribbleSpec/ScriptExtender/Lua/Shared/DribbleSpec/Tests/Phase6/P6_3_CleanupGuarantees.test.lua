local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase6 P6.3 cleanup guarantees", { tags = { "unit", "phase6", "fixture" } }, function()
    Dribble.test("runs fixture teardown for pass and failure paths", function()
        local cleanupCount = 0

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("fixture teardown suite", function()
                dsl.test("pass path", function(ctx)
                    local handle = ctx.fixture.item({
                        provider = "spawn",
                        spawn = function()
                            return {
                                value = "pass",
                                teardown = function()
                                    cleanupCount = cleanupCount + 1
                                end,
                            }
                        end,
                    })
                    Assertions.Equals(handle.value, "pass", "spawned value")
                end)

                dsl.test("failure path", function(ctx)
                    local handle = ctx.fixture.item({
                        provider = "spawn",
                        spawn = function()
                            return {
                                value = "fail",
                                teardown = function()
                                    cleanupCount = cleanupCount + 1
                                end,
                            }
                        end,
                    })
                    Assertions.Equals(handle.value, "fail", "spawned value")
                    error("intentional cleanup failure path")
                end)
            end)
        end)

        Assertions.Equals(run.status, "failed", "nested run status")
        Assertions.Equals(run.summary.passed, 1, "passed count")
        Assertions.Equals(run.summary.failed, 1, "failed count")
        Assertions.Equals(cleanupCount, 2, "teardown count")
    end)
end)
