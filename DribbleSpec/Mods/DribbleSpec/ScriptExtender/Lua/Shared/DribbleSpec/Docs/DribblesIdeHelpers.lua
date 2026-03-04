--- @meta
--- @diagnostic disable

--- Aggregated EmmyLua annotations for the DribbleSpec testing framework public API (1.0.0+).
--- Consumers should include this file in their code-workspace to enable IDE autocomplete and type hints.

---@class DribbleSpecTestOptions
---@field tags? string[] An optional array of tags for filtering (e.g., {"unit", "phase1", "server"})
---@field skip? boolean If true, this test or suite will be unconditionally skipped.
---@field only? boolean If true, only tests/suites marked with `only` will be executed.

---@alias DribbleSpecTestCallback fun(ctx: DribbleSpecTestContext)
---@alias DribbleSpecHookCallback fun(ctx: DribbleSpecTestContext)

---@class DribbleSpecTestContextMeta
---@field suiteName? string
---@field testName? string
---@field fullName string

---@class DribbleSpecExpectationModifier
---@field toBe fun(expected: any)
---@field toEqual fun(expected: any, options?: table)
---@field toBeTruthy fun()
---@field toBeFalsy fun()
---@field toBeNil fun()
---@field toThrow fun(errPattern?: string)
---@field toHaveBeenCalled fun()
---@field toHaveBeenCalledTimes fun(count: integer)
---@field toHaveBeenCalledWith fun(...)
---@field toBeUuid fun()
---@field toBeEntity fun()
---@field toHaveComponent fun(componentName: string)

---@class DribbleSpecExpectation : DribbleSpecExpectationModifier
---@field Not DribbleSpecExpectationModifier Negates the expectation

---@class DribbleSpecFixtureStateApi
---@field snapshot fun(options: table): DribbleSpecFixtureSnapshot
---@field restore fun()

---@class DribbleSpecFixtureSnapshot
---@field restore fun(self: DribbleSpecFixtureSnapshot)

---@class DribbleSpecFixtureApi
---@field entity fun(alias: string, overrides?: table): string Retrieves or spawns an entity fixture and returns its GUID
---@field item fun(alias: string, overrides?: table): string Retrieves or spawns an item fixture and returns its GUID
---@field character fun(alias: string, overrides?: table): string Retrieves or spawns a character fixture and returns its GUID
---@field state DribbleSpecFixtureStateApi State manipulation/snapshotting methods

---@class DribbleSpecTestContext
---@field meta DribbleSpecTestContextMeta Metadata about the currently executing test/suite
---@field expect fun(actual: any): DribbleSpecExpectation Creates an expectation for the given value
---@field mockFn fun(impl?: function): table Creates a new mock function
---@field spyOn fun(target: table, methodName: string): table Replaces a method on a target object with a spy
---@field stub fun(target: table, methodName: string, impl: function): table Replaces a method on a target object with a mock implementation
---@field skip fun(reason?: string) Throws a SkipSignal to bypass the rest of the current test
---@field requireClient fun() Skips the test if it is not running in the client context
---@field requireServer fun() Skips the test if it is not running in the server context
---@field nextTick fun() Advances the engine tick queue
---@field waitUntil fun(predicate: fun():boolean, opts: {timeoutTicks: integer}) Waits until the predicate returns true or timeout is reached
---@field fixture DribbleSpecFixtureApi Fixture management API
---@field entityRef fun(source: any): table Retrieves a stable entity reference

---@class DribbleSpecTestFunction
---@field skip fun(name: string, optionsOrCallback: DribbleSpecTestOptions|DribbleSpecTestCallback, maybeCallback?: DribbleSpecTestCallback)
---@field only fun(name: string, optionsOrCallback: DribbleSpecTestOptions|DribbleSpecTestCallback, maybeCallback?: DribbleSpecTestCallback)
---@operator call(string, DribbleSpecTestOptions|DribbleSpecTestCallback, DribbleSpecTestCallback?): nil

---@class DribbleSpecDescribeFunction
---@field skip fun(name: string, optionsOrCallback: DribbleSpecTestOptions|function, maybeCallback?: function)
---@field only fun(name: string, optionsOrCallback: DribbleSpecTestOptions|function, maybeCallback?: function)
---@operator call(string, DribbleSpecTestOptions|function, function?): nil

---@class DribbleSpecGlobals
---@field describe DribbleSpecDescribeFunction Defines a test suite
---@field test DribbleSpecTestFunction Defines a test case
---@field it DribbleSpecTestFunction Alias for `test`
---@field beforeAll fun(callback: DribbleSpecHookCallback) Registers a hook to run once before all tests in the current suite
---@field beforeEach fun(callback: DribbleSpecHookCallback) Registers a hook to run before each test in the current suite
---@field afterEach fun(callback: DribbleSpecHookCallback) Registers a hook to run after each test in the current suite
---@field afterAll fun(callback: DribbleSpecHookCallback) Registers a hook to run once after all tests in the current suite
---@field expect fun(actual: any): DribbleSpecExpectation Creates an expectation for the given value
---@field entityRef fun(source: any): table Retrieves a stable entity reference
---@field skip fun(reason?: string) Throws a SkipSignal to bypass execution
---@field RunMine fun(options?: table): table Runs tests filtered to the registered owner module
---@field RegisterTestGlobals fun(options?: DribbleSpecRegisterOptions): DribbleSpecGlobals Returns the DribbleSpec API symbols

---@class DribbleSpecRegisterOptions
---@field ownerModuleUUID? string Defaults to current `ModuleUUID` when available
---@field globalTags? string[] Appended to every `describe/test` metadata tags array
---@field commandAlias? string Optional extra console command that runs this mod's tests only

---@param options? DribbleSpecRegisterOptions
---@return DribbleSpecGlobals
function RegisterTestGlobals(options) end

--- RegisterTestGlobals is the primary entrypoint for consumers.
--- Suggested usage: `D = RegisterTestGlobals({ commandAlias = "mytests" })`
---@param options? DribbleSpecRegisterOptions
---@return DribbleSpecGlobals
function Mods.Dribbles.RegisterTestGlobals(options) end

-- Provide autocomplete if users assign to `D` or use it directly
---@type DribbleSpecGlobals
D = {}
---@type DribbleSpecGlobals
Dribble = {}
---@type DribbleSpecGlobals
Dribbles = {}
---@type DribbleSpecGlobals
DribbleSpec = {}
