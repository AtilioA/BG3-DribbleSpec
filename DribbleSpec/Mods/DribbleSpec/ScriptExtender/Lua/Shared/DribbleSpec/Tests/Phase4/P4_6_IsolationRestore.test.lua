local Dribble = _G.Dribble or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

Dribble.describe("DribbleSpec Phase4 P4.6 isolation restore", { tags = { "unit", "phase4", "doubles" } }, function()
    Dribble.test("restores patched methods across test boundaries including failure path", function()
        local shared = {
            sum = function(a, b)
                return a + b
            end,
        }

        local run = RunnerHarness.Run(function(dsl)
            dsl.describe("isolation suite", function()
                dsl.test("spy pass path", function(ctx)
                    local spy = ctx.spyOn(shared, "sum")
                    Assertions.Equals(shared.sum(1, 2), 3, "spy result")
                    ctx.expect(spy).toHaveBeenCalledTimes(1)
                end)

                dsl.test("restored after spy test", function()
                    Assertions.Equals(shared.sum(2, 3), 5, "restored after spy")
                end)

                dsl.test("stub failure path", function(ctx)
                    ctx.stub(shared, "sum", function(a, b)
                        return a * b
                    end)
                    Assertions.Equals(shared.sum(2, 3), 6, "stub result")
                    error("intentional failure after stub")
                end)

                dsl.test("restored after failed stub test", function()
                    Assertions.Equals(shared.sum(2, 3), 5, "restored after failed stub")
                end)
            end)
        end)

        Assertions.Equals(run.status, "failed", "nested run status")
        Assertions.Equals(run.summary.passed, 3, "nested passed count")
        Assertions.Equals(run.summary.failed, 1, "nested failed count")
        Assertions.Equals(run.summary.total, 4, "nested total count")
        Assertions.Contains(run.suites[1].tests[3].error.message, "intentional failure", "failure source")
    end)
end)
