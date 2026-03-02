---@class DribbleRegistrySuite
---@field id integer
---@field name string
---@field metadata table
---@field hooks table
---@field tests table

---@class DribbleRegistry
---@field private _nextOrder integer
---@field private _suites DribbleRegistrySuite[]
local Registry = {}
Registry.__index = Registry

---@return DribbleRegistry
function Registry.Create()
    return setmetatable({
        _nextOrder = 1,
        _suites = {},
    }, Registry)
end

---@return integer
function Registry:NextOrder()
    local current = self._nextOrder
    self._nextOrder = current + 1
    return current
end

---@param name string
---@param metadata table|nil
---@return DribbleRegistrySuite
function Registry:AddSuite(name, metadata)
    local suite = {
        id = self:NextOrder(),
        name = name or ("Suite_" .. tostring(self._nextOrder)),
        metadata = metadata or {},
        hooks = {
            beforeAll = {},
            beforeEach = {},
            afterEach = {},
            afterAll = {},
        },
        tests = {},
    }

    table.insert(self._suites, suite)
    return suite
end

---@return table
function Registry:Snapshot()
    local suites = {}
    for i, suite in ipairs(self._suites) do
        suites[i] = suite
    end

    return {
        suites = suites,
        nextOrder = self._nextOrder,
    }
end

function Registry:Clear()
    self._nextOrder = 1
    self._suites = {}
end

---@return integer
function Registry:SuiteCount()
    return #self._suites
end

return Registry
