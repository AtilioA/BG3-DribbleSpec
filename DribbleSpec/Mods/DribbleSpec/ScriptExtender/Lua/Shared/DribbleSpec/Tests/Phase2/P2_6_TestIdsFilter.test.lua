local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")
local Assertions = Ext.Require("Shared/DribbleSpec/Tests/Support/Assertions.lua")
local RunnerHarness = Ext.Require("Shared/DribbleSpec/Tests/Support/RunnerHarness.lua")

---@param run table
---@return string
local function selectedNames(run)
    local names = {}
    for _, suite in ipairs(run.suites) do
        for _, test in ipairs(suite.tests) do
            table.insert(names, test.fullName .. ":" .. test.status)
        end
    end
    return table.concat(names, "|")
end

---@param dsl table
local function registerSample(dsl)
    dsl.describe("Alpha", { tags = { "fast" } }, function()
        dsl.test("one", function() end)
        dsl.test("two", function() end)
    end)
    dsl.describe("Beta", function()
        dsl.test("one", function() end)
    end)
end

DribbleSpec.describe("DribbleSpec Phase2 P2.6 testIds selection", { tags = { "unit", "phase2", "filter" } }, function()
    DribbleSpec.test("selects tests by exact full name only", function()
        local run = RunnerHarness.Run(registerSample, { testIds = { "Alpha two", "Beta", "alpha one" } })

        Assertions.Equals(run.summary.total, 1, "total count")
        Assertions.Equals(selectedNames(run), "Alpha two:passed", "selected tests")
    end)

    DribbleSpec.test("empty testIds selects no tests", function()
        local run = RunnerHarness.Run(registerSample, { testIds = {} })

        Assertions.Equals(run.summary.total, 0, "total count")
    end)

    DribbleSpec.test("combines with name, tag, and owner filters", function()
        local byName = RunnerHarness.Run(registerSample, { testIds = { "Alpha two", "Beta one" }, namePattern = "one" })
        Assertions.Equals(selectedNames(byName), "Beta one:passed", "name AND")

        local byTag = RunnerHarness.Run(registerSample, { testIds = { "Alpha one", "Beta one" }, tags = { "fast" } })
        Assertions.Equals(selectedNames(byTag), "Alpha one:passed", "tag AND")

        local function registerOwned(dsl)
            dsl.describe("Alpha", function()
                dsl.test("one", function() end)
            end)
            dsl.describe("Beta", { ownerModuleUUID = "owner-x" }, function()
                dsl.test("one", function() end)
            end)
        end

        local ownerExcluded = RunnerHarness.Run(registerOwned, { testIds = { "Alpha one" }, ownerModuleUUID = "owner-x" })
        Assertions.Equals(ownerExcluded.summary.total, 0, "owner AND excludes")

        local ownerKept = RunnerHarness.Run(registerOwned, { testIds = { "Beta one" }, ownerModuleUUID = "owner-x" })
        Assertions.Equals(selectedNames(ownerKept), "Beta one:passed", "owner AND keeps")
    end)

    DribbleSpec.test("Run rejects testIds that are not an array of strings", function()
        -- The no-match owner keeps a regression from running the live registry.
        local ok, err = pcall(DribbleSpec.Run, { testIds = "Alpha one", ownerModuleUUID = "__none__" })
        Assertions.Equals(ok, false, "string testIds raises")
        Assertions.Contains(tostring(err), "testIds", "error names option")

        local okMixed = pcall(DribbleSpec.Run, { testIds = { "Alpha one", 2 }, ownerModuleUUID = "__none__" })
        Assertions.Equals(okMixed, false, "non-string entry raises")
    end)

    DribbleSpec.test("ignores .only focus when testIds is set", function()
        local function register(dsl)
            dsl.describe("Focused", function()
                dsl.test.only("target", function() end)
            end)
            dsl.describe("Other", function()
                dsl.test("picked", function() end)
            end)
        end

        local run = RunnerHarness.Run(register, { testIds = { "Other picked" } })
        Assertions.Equals(selectedNames(run), "Other picked:passed", "selected test runs")

        local focused = RunnerHarness.Run(register, {})
        Assertions.Equals(selectedNames(focused), "Focused target:passed|Other picked:skipped", "focus without testIds")
    end)
end)
