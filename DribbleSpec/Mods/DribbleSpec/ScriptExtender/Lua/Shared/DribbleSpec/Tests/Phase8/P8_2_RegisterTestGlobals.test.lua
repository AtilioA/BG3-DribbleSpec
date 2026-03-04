local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")

DribbleSpec.describe("DribbleSpec Phase8 P8.2 RegisterTestGlobals", { tags = { "unit", "phase8", "consumer" } },
    function()
        DribbleSpec.test("framework RegisterTestGlobals entrypoints are available", function()
            Assertions.Equals(type(rawget(_G, "RegisterTestGlobals")), "function", "global register function")
            Assertions.Equals(type(DribbleSpec.RegisterTestGlobals), "function", "DribbleSpec register function")
        end)

        DribbleSpec.test("RegisterTestGlobals adds public symbols into target namespace", function()
            local target = RegisterTestGlobals()

            Assertions.Equals(type(target.describe), "function", "describe exposed")
            Assertions.Equals(type(target.test), "table", "test exposed")
            Assertions.Equals(type(target.it), "table", "it exposed")
            Assertions.Equals(type(target.beforeAll), "function", "beforeAll exposed")
            Assertions.Equals(type(target.afterAll), "function", "afterAll exposed")
            Assertions.Equals(type(target.expect), "function", "expect exposed")
            Assertions.Equals(type(target.entityRef), "function", "entityRef exposed")
            Assertions.Equals(type(target.RegisterTestGlobals), "function", "RegisterTestGlobals exposed")
            Assertions.Equals(type(target.RunMine), "function", "RunMine exposed")
        end)

        DribbleSpec.test("RegisterTestGlobals returns fresh table snapshots", function()
            local first = RegisterTestGlobals()
            local second = RegisterTestGlobals()

            Assertions.Equals(first.describe == second.describe, false, "describe wrapper isolation")
            Assertions.Equals(first.test == second.test, false, "test wrapper isolation")
            Assertions.Equals(first == second, false, "separate export tables")
        end)

        DribbleSpec.test("RegisterTestGlobals options inject owner and global tags into describe/test", function()
            local originalDescribe = DribbleSpec.describe
            local originalTest = DribbleSpec.test
            local capturedDescribeMetadata = nil
            local capturedTestMetadata = nil

            local ok, err = xpcall(function()
                DribbleSpec.describe = function(_, metadata)
                    capturedDescribeMetadata = metadata
                end

                DribbleSpec.test = setmetatable({
                    skip = function(_, metadata)
                        capturedTestMetadata = metadata
                    end,
                    only = function(_, metadata)
                        capturedTestMetadata = metadata
                    end,
                }, {
                    __call = function(_, _, metadata)
                        capturedTestMetadata = metadata
                    end,
                })

                local exports = RegisterTestGlobals({
                    ownerModuleUUID = "mod-owner-1",
                    globalTags = { "consumer", "smoke" },
                })

                exports.describe("wrapped suite", function()
                end)
                exports.test("wrapped test", function()
                end)

                Assertions.Equals(capturedDescribeMetadata.ownerModuleUUID, "mod-owner-1", "describe owner metadata")
                Assertions.Equals(capturedTestMetadata.ownerModuleUUID, "mod-owner-1", "test owner metadata")
                Assertions.Equals(type(capturedDescribeMetadata.tags), "table", "describe tags table")
                Assertions.Equals(type(capturedTestMetadata.tags), "table", "test tags table")
                Assertions.Equals(capturedDescribeMetadata.tags[1], "consumer", "describe first tag")
                Assertions.Equals(capturedDescribeMetadata.tags[2], "smoke", "describe second tag")
                Assertions.Equals(capturedTestMetadata.tags[1], "consumer", "test first tag")
                Assertions.Equals(capturedTestMetadata.tags[2], "smoke", "test second tag")
            end, debug.traceback)

            DribbleSpec.describe = originalDescribe
            DribbleSpec.test = originalTest

            if not ok then
                error(err)
            end
        end)

        DribbleSpec.test("RegisterTestGlobals exports RunMine with ownerModuleUUID option", function()
            local exports = RegisterTestGlobals({ ownerModuleUUID = "mod-owner-2" })
            local run = exports.RunMine()

            Assertions.Equals(type(exports.RunMine), "function", "RunMine export")
            Assertions.Equals(run.options.ownerModuleUUID, "mod-owner-2", "run owner option")
        end)
    end)
