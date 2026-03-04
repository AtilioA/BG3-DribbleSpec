local DribbleSpec = _G.DribbleSpec or Ext.Require("Shared/DribbleSpec/init.lua")

local function assertEquals(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", tostring(label), tostring(expected), tostring(actual)))
    end
end

local function assertSequence(actual, expected, label)
    if #actual ~= #expected then
        error(string.format("%s: expected length %d, got %d", tostring(label), #expected, #actual))
    end

    for i = 1, #expected do
        if actual[i] ~= expected[i] then
            error(string.format("%s: mismatch at index %d (expected '%s', got '%s')", tostring(label), i,
                tostring(expected[i]), tostring(actual[i])))
        end
    end
end

local order = {}
local skippedExecuted = false
local crossSuiteAfterAllRan = false

DribbleSpec.describe("DribbleSpec Phase1 Smoke", { tags = { "unit", "phase1" } }, function()
    DribbleSpec.beforeAll(function()
        order = {}
        skippedExecuted = false
        crossSuiteAfterAllRan = false
        table.insert(order, "beforeAll")
    end)

    DribbleSpec.beforeEach(function()
        table.insert(order, "beforeEach")
    end)

    DribbleSpec.afterEach(function()
        table.insert(order, "afterEach")
    end)

    DribbleSpec.afterAll(function()
        crossSuiteAfterAllRan = true
    end)

    DribbleSpec.test("executes first test", function()
        assertSequence(order, { "beforeAll", "beforeEach" }, "first test hook order")
        table.insert(order, "test1")
    end)

    DribbleSpec.test.skip("skipped body does not execute", function()
        skippedExecuted = true
    end)

    DribbleSpec.it("executes second test and verifies skip behavior", function()
        assertEquals(skippedExecuted, false, "skipped test body should not run")
        assertSequence(order, {
            "beforeAll",
            "beforeEach",
            "test1",
            "afterEach",
            "beforeEach",
        }, "second test precondition order")
        table.insert(order, "test2")
    end)

    DribbleSpec.test("beforeEach/afterEach continue to wrap each executed test", function()
        assertSequence(order, {
            "beforeAll",
            "beforeEach",
            "test1",
            "afterEach",
            "beforeEach",
            "test2",
            "afterEach",
            "beforeEach",
        }, "third test precondition order")
    end)
end)

DribbleSpec.describe("DribbleSpec Phase1 CrossSuite", { tags = { "unit", "phase1" } }, function()
    DribbleSpec.test("afterAll from previous suite ran before next suite starts", function()
        assertEquals(crossSuiteAfterAllRan, true, "afterAll should run before next suite test")
    end)
end)
