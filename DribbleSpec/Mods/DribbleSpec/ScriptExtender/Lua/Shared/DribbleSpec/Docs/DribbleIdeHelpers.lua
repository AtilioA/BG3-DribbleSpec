--- @meta
--- @diagnostic disable

--- Aggregated EmmyLua annotations for the DribbleSpec testing framework public API (1.0.0+).
--- Consumers should include this file in their code-workspace to enable IDE autocomplete and type hints.

---@class DribbleTestOptions
---@field tags? string[] An optional array of tags for filtering (e.g., {"unit", "phase1", "server"})
---@field skip? boolean If true, this test or suite will be unconditionally skipped.
---@field only? boolean If true, only tests/suites marked with `only` will be executed.

---@alias DribbleTestCallback fun(ctx: DribbleTestContext)
---@alias DribbleHookCallback fun(ctx: DribbleTestContext)

---@class DribbleTestContextMeta
---@field suiteName? string
---@field testName? string
---@field fullName string

---@class DribbleExpectationModifier
---@field toBe fun(expected: any)
---@field toEqual fun(expected: any, options?: table)
---@field toBeTruthy fun()
---@field toBeFalsy fun()
---@field toBeNil fun()
---@field toThrow fun(errPattern?: string)
---@field toHaveBeenCalled fun()
---@field toHaveBeenCalledTimes fun(count: integer)
---@field toHaveBeenCalledWith fun(...)
---@field toBeGuid fun()
---@field toBeEntity fun()
---@field toHaveComponent fun(componentName: string)

---@class DribbleExpectation : DribbleExpectationModifier
---@field Not DribbleExpectationModifier Negates the expectation

---@class DribbleFixtureStateApi
---@field snapshot fun(options: table): DribbleFixtureSnapshot
---@field restore fun()

---@class DribbleFixtureSnapshot
---@field restore fun(self: DribbleFixtureSnapshot)

---@class DribbleFixtureApi
---@field entity fun(alias: string, overrides?: table): string Retrieves or spawns an entity fixture and returns its GUID
---@field item fun(alias: string, overrides?: table): string Retrieves or spawns an item fixture and returns its GUID
---@field character fun(alias: string, overrides?: table): string Retrieves or spawns a character fixture and returns its GUID
---@field state DribbleFixtureStateApi State manipulation/snapshotting methods

---@class DribbleTestContext
---@field meta DribbleTestContextMeta Metadata about the currently executing test/suite
---@field expect fun(actual: any): DribbleExpectation Creates an expectation for the given value
---@field mockFn fun(impl?: function): table Creates a new mock function
---@field spyOn fun(target: table, methodName: string): table Replaces a method on a target object with a spy
---@field stub fun(target: table, methodName: string, impl: function): table Replaces a method on a target object with a mock implementation
---@field skip fun(reason?: string) Throws a SkipSignal to bypass the rest of the current test
---@field requireClient fun() Skips the test if it is not running in the client context
---@field requireServer fun() Skips the test if it is not running in the server context
---@field nextTick fun() Advances the engine tick queue
---@field waitUntil fun(predicate: fun():boolean, opts: {timeoutTicks: integer}) Waits until the predicate returns true or timeout is reached
---@field fixture DribbleFixtureApi Fixture management API
---@field entityRef fun(source: any): table Retrieves a stable entity reference

---@class DribbleTestFunction
---@field skip fun(name: string, optionsOrCallback: DribbleTestOptions|DribbleTestCallback, maybeCallback?: DribbleTestCallback)
---@field only fun(name: string, optionsOrCallback: DribbleTestOptions|DribbleTestCallback, maybeCallback?: DribbleTestCallback)
---@operator call(string, DribbleTestOptions|DribbleTestCallback, DribbleTestCallback?): nil

---@class DribbleDescribeFunction
---@field skip fun(name: string, optionsOrCallback: DribbleTestOptions|function, maybeCallback?: function)
---@field only fun(name: string, optionsOrCallback: DribbleTestOptions|function, maybeCallback?: function)
---@operator call(string, DribbleTestOptions|function, function?): nil

---@class DribbleGlobals
---@field describe DribbleDescribeFunction Defines a test suite
---@field test DribbleTestFunction Defines a test case
---@field it DribbleTestFunction Alias for `test`
---@field beforeAll fun(callback: DribbleHookCallback) Registers a hook to run once before all tests in the current suite
---@field beforeEach fun(callback: DribbleHookCallback) Registers a hook to run before each test in the current suite
---@field afterEach fun(callback: DribbleHookCallback) Registers a hook to run after each test in the current suite
---@field afterAll fun(callback: DribbleHookCallback) Registers a hook to run once after all tests in the current suite
---@field expect fun(actual: any): DribbleExpectation Creates an expectation for the given value
---@field entityRef fun(source: any): table Retrieves a stable entity reference
---@field skip fun(reason?: string) Throws a SkipSignal to bypass execution
---@field RegisterTestGlobals fun(): DribbleGlobals Returns the DribbleSpec API symbols

--- RegisterTestGlobals is the primary entrypoint for consumers.
--- Suggested usage: `D = RegisterTestGlobals()`
---@return DribbleGlobals
function RegisterTestGlobals() end

-- Provide autocomplete if users assign to `D` or use it directly
---@type DribbleGlobals
Dribble = {}
