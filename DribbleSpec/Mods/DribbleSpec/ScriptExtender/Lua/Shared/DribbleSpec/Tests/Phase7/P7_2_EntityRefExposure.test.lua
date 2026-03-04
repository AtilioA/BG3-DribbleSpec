local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

DribbleSpec.describe("DribbleSpec Phase7 P7.2 entityRef exposure", { tags = { "unit", "phase7", "entity" } }, function()
    DribbleSpec.test("ctx exposes entityRef helper", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("entityRef context suite", function()
                dsl.test("ctx.entityRef exists", function(ctx)
                    Assertions.Equals(type(ctx.entityRef), "function", "entityRef helper type")

                    local ref = ctx.entityRef(function()
                        return {
                            GetComponent = function(_, componentName)
                                if componentName == "DisplayName" then
                                    return {
                                        Name = "helper",
                                    }
                                end

                                return nil
                            end,
                        }
                    end)

                    ctx.expect(ref).toBeEntity()
                end)
            end)
        end)

        Assertions.Equals(run.status, "passed", "nested run status")
    end)

    DribbleSpec.test("fixture handles include ref for resolvable entity fixtures", function()
        local fakeEntity = {
            GetComponent = function(_, componentName)
                if componentName == "DisplayName" then
                    return {
                        Name = "fixture",
                    }
                end

                return nil
            end,
        }

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("fixture ref suite", function()
                dsl.test("entity fixture includes ref", function(ctx)
                    local handle = ctx.fixture.entity("known")
                    Assertions.Equals(type(handle.ref), "table", "fixture ref type")
                    Assertions.Equals(handle.ref:IsEntityRef(), true, "fixture ref marker")
                    ctx.expect(handle.ref).toBeEntity()
                end)
            end)
        end, {
            fixtureProviders = {
                {
                    name = "preplaced",
                    Resolve = function()
                        return {
                            value = fakeEntity,
                            guid = "58a69333-40bf-8358-1d17-fff240d7fb12",
                        }
                    end,
                },
            },
        })

        Assertions.Equals(run.status, "passed", "nested run status")
    end)

    DribbleSpec.test("fixture handles keep ref nil when fixture is not entity-like", function()
        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("non entity fixture suite", function()
                dsl.test("string fixture has no ref", function(ctx)
                    local handle = ctx.fixture.item("spawned")
                    Assertions.Equals(handle.ref, nil, "non entity ref")
                end)
            end)
        end, {
            fixtureProviders = {
                {
                    name = "preplaced",
                    Resolve = function()
                        return nil
                    end,
                },
                {
                    name = "spawn",
                    Resolve = function()
                        return {
                            value = "spawned",
                        }
                    end,
                },
            },
        })

        Assertions.Equals(run.status, "passed", "nested run status")
    end)
end)
