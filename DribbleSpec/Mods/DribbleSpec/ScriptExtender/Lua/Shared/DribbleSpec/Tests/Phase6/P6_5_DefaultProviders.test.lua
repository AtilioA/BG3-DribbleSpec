local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

DribbleSpec.describe("DribbleSpec Phase6 P6.5 default providers", { tags = { "unit", "phase6", "fixture" } }, function()
    DribbleSpec.test("default preplaced provider resolves aliases via Ext.Entity.Get", function()
        local calls = 0
        local resolvedEntity = {
            Guid = "known-guid",
        }

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("default preplaced suite", function()
                dsl.test("alias resolve", function(ctx)
                    local handle = ctx.fixture.entity("vendor")
                    Assertions.Equals(type(handle.value), "table", "resolved value type")
                    Assertions.Equals(handle.guid, "known-guid", "resolved guid")
                    Assertions.Equals(handle.provider, "preplaced", "resolved provider")
                    Assertions.Equals(handle.value.Guid, "known-guid", "resolved alias entity")
                end)
            end)
        end, {
            fixtureAliases = {
                entity = {
                    vendor = {
                        guid = "known-guid",
                        resolve = function(descriptor, _)
                            calls = calls + 1
                            Assertions.Equals(descriptor.guid, "known-guid", "descriptor guid")
                            return resolvedEntity
                        end,
                    },
                },
            },
        })

        Assertions.Equals(run.status, "passed", "nested run status")
        Assertions.Equals(calls, 1, "resolve call count")
    end)

    DribbleSpec.test("default spawn provider supports spawn function and cleanup", function()
        local cleanupCount = 0

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("default spawn suite", function()
                dsl.test("spawn fallback", function(ctx)
                    local handle = ctx.fixture.item({
                        alias = "missing",
                        spawn = function()
                            return {
                                value = "spawned",
                            }
                        end,
                        cleanup = function()
                            cleanupCount = cleanupCount + 1
                        end,
                    })

                    Assertions.Equals(handle.value, "spawned", "spawned value")
                    Assertions.Equals(handle.provider, "spawn", "spawn provider")
                end)
            end)
        end)

        Assertions.Equals(run.status, "passed", "nested run status")
        Assertions.Equals(cleanupCount, 1, "cleanup calls")
    end)
end)
