local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase6 P6.4 state snapshot restore", { tags = { "unit", "phase6", "fixture" } }, function()
    Dribble.test("restores snapshot state across test boundaries", function()
        local sharedState = {
            mode = "original",
        }

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("state restore suite", function()
                dsl.test("mutates state after snapshot", function(ctx)
                    ctx.fixture.state.snapshot({
                        captures = {
                            {
                                get = function()
                                    return sharedState.mode
                                end,
                                set = function(value)
                                    sharedState.mode = value
                                end,
                            },
                        },
                    })

                    sharedState.mode = "changed"
                    Assertions.Equals(sharedState.mode, "changed", "mutated state")
                end)

                dsl.test("state is restored before next test", function()
                    Assertions.Equals(sharedState.mode, "original", "restored state")
                end)
            end)
        end)

        Assertions.Equals(run.status, "passed", "nested run status")
        Assertions.Equals(run.summary.passed, 2, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
    end)

    Dribble.test("manual state restore is idempotent", function()
        local sharedState = {
            value = 10,
        }
        local setCalls = 0

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("manual restore suite", function()
                dsl.test("manual restore", function(ctx)
                    ctx.fixture.state.snapshot({
                        get = function()
                            return sharedState.value
                        end,
                        set = function(value)
                            setCalls = setCalls + 1
                            sharedState.value = value
                        end,
                    })

                    sharedState.value = 25
                    local firstRestore = ctx.fixture.state.restore()
                    local secondRestore = ctx.fixture.state.restore()

                    Assertions.Equals(firstRestore, 1, "first restore count")
                    Assertions.Equals(secondRestore, 0, "second restore count")
                    Assertions.Equals(sharedState.value, 10, "restored value")
                end)

                dsl.test("does not restore twice during sandbox cleanup", function()
                    Assertions.Equals(sharedState.value, 10, "shared state")
                    Assertions.Equals(setCalls, 1, "set calls")
                end)
            end)
        end)

        Assertions.Equals(run.status, "passed", "nested run status")
        Assertions.Equals(run.summary.passed, 2, "passed count")
        Assertions.Equals(run.summary.failed, 0, "failed count")
    end)
end)
