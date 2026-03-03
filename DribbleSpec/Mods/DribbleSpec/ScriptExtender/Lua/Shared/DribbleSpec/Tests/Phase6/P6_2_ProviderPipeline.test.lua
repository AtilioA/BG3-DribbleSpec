local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase6 P6.2 provider pipeline", { tags = { "unit", "phase6", "fixture" } }, function()
    Dribble.test("uses preplaced provider before spawn provider", function()
        local calls = {}
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("provider order suite", function()
                dsl.test("preplaced match", function(ctx)
                    local handle = ctx.fixture.entity("vendor")
                    Assertions.Equals(handle.value, "from-preplaced", "resolved handle")
                    Assertions.Equals(handle.provider, "preplaced", "provider name")
                end)
            end)
        end, {
            fixtureProviders = {
                {
                    name = "preplaced",
                    Resolve = function(_, _, _, _)
                        table.insert(calls, "preplaced")
                        return { value = "from-preplaced" }
                    end,
                },
                {
                    name = "spawn",
                    Resolve = function(_, _, _, _)
                        table.insert(calls, "spawn")
                        return { value = "from-spawn" }
                    end,
                },
            },
        })

        Assertions.Equals(run.status, "passed", "nested run status")
        Assertions.Equals(#calls, 1, "provider call count")
        Assertions.Equals(calls[1], "preplaced", "provider first")
    end)

    Dribble.test("falls back to spawn provider when preplaced misses", function()
        local calls = {}
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("provider fallback suite", function()
                dsl.test("spawn fallback", function(ctx)
                    local handle = ctx.fixture.item("spawn-only")
                    Assertions.Equals(handle.value, "from-spawn", "resolved handle")
                    Assertions.Equals(handle.provider, "spawn", "provider name")
                end)
            end)
        end, {
            fixtureProviders = {
                {
                    name = "preplaced",
                    Resolve = function(_, _, _, _)
                        table.insert(calls, "preplaced")
                        return nil
                    end,
                },
                {
                    name = "spawn",
                    Resolve = function(_, _, _, _)
                        table.insert(calls, "spawn")
                        return { value = "from-spawn" }
                    end,
                },
            },
        })

        Assertions.Equals(run.status, "passed", "nested run status")
        Assertions.Equals(#calls, 2, "provider call count")
        Assertions.Equals(calls[1], "preplaced", "provider first")
        Assertions.Equals(calls[2], "spawn", "provider second")
    end)

    Dribble.test("supports explicit provider targeting", function()
        local calls = {}
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("explicit provider suite", function()
                dsl.test("spawn only", function(ctx)
                    local handle = ctx.fixture.entity({
                        provider = "spawn",
                        spawn = function()
                            return { value = "spawned-value" }
                        end,
                    })
                    Assertions.Equals(handle.value, "spawned-value", "spawn value")
                    Assertions.Equals(handle.provider, "spawn", "spawn provider")
                end)
            end)
        end, {
            fixtureProviders = {
                {
                    name = "preplaced",
                    Resolve = function(_, _, _, _)
                        table.insert(calls, "preplaced")
                        return { value = "unexpected" }
                    end,
                },
                {
                    name = "spawn",
                    Resolve = function(_, _, spec, _)
                        table.insert(calls, "spawn")
                        return spec.spawn()
                    end,
                },
            },
        })

        Assertions.Equals(run.status, "passed", "nested run status")
        Assertions.Equals(#calls, 1, "provider call count")
        Assertions.Equals(calls[1], "spawn", "targeted provider")
    end)
end)
