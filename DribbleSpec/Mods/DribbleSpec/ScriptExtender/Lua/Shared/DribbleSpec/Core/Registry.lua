---@class DribbleSpecRegistrySuite
---@field id integer
---@field name string
---@field fullName string
---@field metadata table
---@field hooks table
---@field tests table
---@field suites DribbleSpecRegistrySuite[]
---@field parent DribbleSpecRegistrySuite|nil
---@field only boolean
---@field skip boolean

---@class DribbleSpecRegistryTest
---@field id integer
---@field name string
---@field fullName string
---@field metadata table
---@field callback function
---@field only boolean
---@field skip boolean

---@class DribbleSpecRegistry
---@field private _nextOrder integer
---@field private _rootSuites DribbleSpecRegistrySuite[]
---@field private _suiteStack DribbleSpecRegistrySuite[]
---@field private _hasOnly boolean
local Registry = {}
Registry.__index = Registry

---@param metadata table|nil
---@return table
local function normalizeMetadata(metadata)
    local normalized = metadata or {}
    if type(normalized) ~= "table" then
        normalized = {}
    end

    if type(normalized.tags) ~= "table" then
        normalized.tags = {}
    end

    return normalized
end

---@return DribbleSpecRegistry
function Registry.Create()
    return setmetatable({
        _nextOrder = 1,
        _rootSuites = {},
        _suiteStack = {},
        _hasOnly = false,
    }, Registry)
end

---@return integer
function Registry:NextOrder()
    local current = self._nextOrder
    self._nextOrder = current + 1
    return current
end

---@return DribbleSpecRegistrySuite|nil
function Registry:CurrentSuite()
    return self._suiteStack[#self._suiteStack]
end

---@param name string
---@param metadata table|nil
---@return DribbleSpecRegistrySuite
function Registry:BeginSuite(name, metadata)
    if type(name) ~= "string" or name == "" then
        error("describe() requires a non-empty suite name", 2)
    end

    local normalizedMetadata = normalizeMetadata(metadata)
    local parent = self:CurrentSuite()
    local fullName = name
    if parent then
        fullName = string.format("%s %s", parent.fullName, name)
    end

    local suite = {
        id = self:NextOrder(),
        name = name,
        fullName = fullName,
        metadata = normalizedMetadata,
        hooks = {
            beforeAll = {},
            beforeEach = {},
            afterEach = {},
            afterAll = {},
        },
        tests = {},
        suites = {},
        parent = parent,
        only = normalizedMetadata.only == true,
        skip = normalizedMetadata.skip == true,
    }

    if parent then
        table.insert(parent.suites, suite)
    else
        table.insert(self._rootSuites, suite)
    end

    table.insert(self._suiteStack, suite)
    if suite.only then
        self._hasOnly = true
    end

    return suite
end

---@return DribbleSpecRegistrySuite
function Registry:EndSuite()
    local suite = table.remove(self._suiteStack)
    if not suite then
        error("describe() scope mismatch: no suite to end", 2)
    end

    return suite
end

---@param hookName "beforeAll"|"beforeEach"|"afterEach"|"afterAll"
---@param callback function
---@return table
function Registry:AddHook(hookName, callback)
    local suite = self:CurrentSuite()
    if not suite then
        error(string.format("%s() must be called inside describe()", hookName), 2)
    end

    if type(callback) ~= "function" then
        error(string.format("%s() requires a function callback", hookName), 2)
    end

    local hooks = suite.hooks[hookName]
    if type(hooks) ~= "table" then
        error(string.format("Unknown hook '%s'", hookName), 2)
    end

    local hook = {
        id = self:NextOrder(),
        callback = callback,
    }
    table.insert(hooks, hook)
    return hook
end

---@param name string
---@param metadata table|nil
---@param callback function
---@return DribbleSpecRegistryTest
function Registry:AddTest(name, metadata, callback)
    local suite = self:CurrentSuite()
    if not suite then
        error("test() must be called inside describe()", 2)
    end

    if type(name) ~= "string" or name == "" then
        error("test() requires a non-empty test name", 2)
    end

    if type(callback) ~= "function" then
        error("test() requires a function callback", 2)
    end

    local normalizedMetadata = normalizeMetadata(metadata)
    local test = {
        id = self:NextOrder(),
        name = name,
        fullName = string.format("%s %s", suite.fullName, name),
        metadata = normalizedMetadata,
        callback = callback,
        only = normalizedMetadata.only == true,
        skip = normalizedMetadata.skip == true,
    }

    table.insert(suite.tests, test)
    if test.only then
        self._hasOnly = true
    end

    return test
end

---@return boolean
function Registry:HasOnly()
    return self._hasOnly == true
end

---@return table
function Registry:Snapshot()
    local suites = {}
    for i, suite in ipairs(self._rootSuites) do
        suites[i] = suite
    end

    return {
        suites = suites,
        nextOrder = self._nextOrder,
        hasOnly = self._hasOnly,
    }
end

function Registry:Clear()
    self._nextOrder = 1
    self._rootSuites = {}
    self._suiteStack = {}
    self._hasOnly = false
end

---@return integer
function Registry:SuiteCount()
    return #self._rootSuites
end

return Registry
