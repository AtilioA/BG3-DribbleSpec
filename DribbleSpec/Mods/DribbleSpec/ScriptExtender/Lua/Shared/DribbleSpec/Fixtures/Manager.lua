local PreplacedProvider = Ext.Require("Shared/DribbleSpec/Fixtures/Providers/PreplacedProvider.lua")
local SpawnProvider = Ext.Require("Shared/DribbleSpec/Fixtures/Providers/SpawnProvider.lua")
local EntityRef = Ext.Require("Shared/DribbleSpec/Entity/EntityRef.lua")

---@class DribbleSpecFixtureManager
---@field private _sandbox table
---@field private _providers table[]
---@field private _providerContext table
---@field private _stateSnapshots function[]
local Manager = {}
Manager.__index = Manager

---@param value any
---@param seen table|nil
---@return any
local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end

    local refs = seen or {}
    if refs[value] ~= nil then
        return refs[value]
    end

    local clone = {}
    refs[value] = clone
    for k, v in pairs(value) do
        clone[deepCopy(k, refs)] = deepCopy(v, refs)
    end

    return clone
end

---@param value any
---@param cloneStrategy function|boolean|nil
---@return any
local function cloneValue(value, cloneStrategy)
    if type(cloneStrategy) == "function" then
        return cloneStrategy(value)
    end

    if cloneStrategy == false then
        return value
    end

    return deepCopy(value)
end

---@param value table
---@return table
local function shallowCopy(value)
    local copy = {}
    for k, v in pairs(value or {}) do
        copy[k] = v
    end

    return copy
end

---@param kind string
---@param aliasOrSpec any
---@return table
local function normalizeSpec(kind, aliasOrSpec)
    local valueType = type(aliasOrSpec)
    if valueType == "string" then
        return {
            alias = aliasOrSpec,
        }
    end

    if valueType == "table" then
        return shallowCopy(aliasOrSpec)
    end

    error(string.format("ctx.fixture.%s(aliasOrSpec) expects string or table", tostring(kind)), 3)
end

---@param context string
---@param options table
---@param suite table|nil
---@param test table|nil
---@return table[]
local function buildDefaultProviders(context, options, suite, test)
    local aliases = (options and options.fixtureAliases) or {}

    return {
        PreplacedProvider.Create({
            aliases = aliases,
        }),
        SpawnProvider.Create({
            spawner = options and options.fixtureSpawner or nil,
            context = context,
            suite = suite,
            test = test,
        }),
    }
end

---@param provider table
---@param spec table
---@return boolean
local function shouldUseProvider(provider, spec)
    local forcedProvider = spec.provider
    if type(forcedProvider) ~= "string" or forcedProvider == "" then
        return true
    end

    return tostring(provider.name) == forcedProvider
end

---@param self DribbleSpecFixtureManager
---@param handle table
local function trackHandleTeardown(self, handle)
    if type(handle.teardown) ~= "function" then
        return
    end

    local teardownDone = false
    local teardown = handle.teardown
    local context = self._providerContext

    local function restoreHandle()
        if teardownDone then
            return
        end

        teardownDone = true
        pcall(teardown, handle, context)
    end

    handle.restore = restoreHandle
    self._sandbox:TrackRestore(restoreHandle)
end

---@param self DribbleSpecFixtureManager
---@param kind string
---@param spec table
---@param providerName string
---@param resolved table|any
---@return table
local function finalizeHandle(self, kind, spec, providerName, resolved)
    local handle = nil
    if type(resolved) == "table" then
        handle = shallowCopy(resolved)
    else
        handle = {
            value = resolved,
        }
    end

    if handle.value == nil then
        if handle.entity ~= nil then
            handle.value = handle.entity
        elseif handle.result ~= nil then
            handle.value = handle.result
        end
    end

    if handle.guid == nil then
        handle.guid = spec.guid or spec.uuid or spec.entityGuid
    end

    if handle.netId == nil then
        handle.netId = spec.netId
    end

    if type(handle.teardown) ~= "function" and type(spec.cleanup) == "function" then
        handle.teardown = spec.cleanup
    end

    handle.kind = kind
    handle.provider = providerName
    handle.spec = spec

    local ref = EntityRef.TryCreate({
        guid = handle.guid,
        netId = handle.netId,
        value = handle.value,
        resolve = handle.resolve,
    })
    if ref ~= nil then
        handle.ref = ref
    end

    trackHandleTeardown(self, handle)
    return handle
end

---@param params table
---@return DribbleSpecFixtureManager
function Manager.Create(params)
    local options = params.options or {}
    local providers = params.providers or options.fixtureProviders
    if type(providers) ~= "table" then
        providers = buildDefaultProviders(params.context, options, params.suite, params.test)
    end

    return setmetatable({
        _sandbox = params.sandbox,
        _providers = providers,
        _providerContext = {
            context = params.context,
            options = options,
            suite = params.suite,
            test = params.test,
        },
        _stateSnapshots = {},
    }, Manager)
end

---@param kind string
---@param aliasOrSpec any
---@return table
function Manager:Resolve(kind, aliasOrSpec)
    local spec = normalizeSpec(kind, aliasOrSpec)
    local lastError = nil
    local attempted = 0

    for _, provider in ipairs(self._providers) do
        if shouldUseProvider(provider, spec) and type(provider.Resolve) == "function" then
            attempted = attempted + 1
            local ok, resolved, providerErr = pcall(provider.Resolve, provider, kind, spec, self._providerContext)
            if not ok then
                lastError = tostring(resolved)
            elseif resolved ~= nil then
                return finalizeHandle(self, kind, spec, tostring(provider.name or "provider"), resolved)
            elseif providerErr then
                lastError = tostring(providerErr)
            end
        end
    end

    if attempted == 0 then
        error(string.format("Unknown fixture provider '%s'", tostring(spec.provider)), 3)
    end

    if lastError then
        error(lastError, 3)
    end

    error(string.format("No fixture provider could resolve %s fixture", tostring(kind)), 3)
end

---@param spec table
---@return table[]
local function normalizeSnapshotSpec(spec)
    if type(spec) ~= "table" then
        error("ctx.fixture.state.snapshot(spec) expects a table", 3)
    end

    if type(spec.get) == "function" and type(spec.set) == "function" then
        return { spec }
    end

    if type(spec.captures) ~= "table" or #spec.captures == 0 then
        error("ctx.fixture.state.snapshot(spec) requires captures with get/set", 3)
    end

    return spec.captures
end

---@param spec table
---@return table
function Manager:SnapshotState(spec)
    local captures = normalizeSnapshotSpec(spec)
    local restorers = {}

    for _, capture in ipairs(captures) do
        if type(capture.get) ~= "function" or type(capture.set) ~= "function" then
            error("ctx.fixture.state.snapshot capture requires get and set functions", 3)
        end

        local ok, currentOrErr = pcall(capture.get)
        if not ok then
            error(string.format("state snapshot capture failed: %s", tostring(currentOrErr)), 3)
        end

        local savedValue = cloneValue(currentOrErr, capture.clone)
        local restoreDone = false
        local function restoreCapture()
            if restoreDone then
                return false
            end

            restoreDone = true
            pcall(capture.set, cloneValue(savedValue, capture.clone))
            return true
        end

        table.insert(restorers, 1, restoreCapture)
    end

    local snapshotDone = false
    local function restoreSnapshot()
        if snapshotDone then
            return 0
        end

        snapshotDone = true
        local restoredCount = 0
        for _, restoreCapture in ipairs(restorers) do
            if restoreCapture() then
                restoredCount = restoredCount + 1
            end
        end

        return restoredCount
    end

    local snapshot = {
        restore = restoreSnapshot,
    }

    table.insert(self._stateSnapshots, 1, snapshot)
    self._sandbox:TrackRestore(restoreSnapshot)
    return snapshot
end

---@return integer
function Manager:RestoreState()
    local restoredCount = 0

    for _, snapshot in ipairs(self._stateSnapshots) do
        if type(snapshot.restore) == "function" then
            local ok, restored = pcall(snapshot.restore)
            if ok and type(restored) == "number" then
                restoredCount = restoredCount + restored
            end
        end
    end

    self._stateSnapshots = {}
    return restoredCount
end

---@return table
function Manager:BuildApi()
    return {
        character = function(aliasOrSpec)
            return self:Resolve("character", aliasOrSpec)
        end,
        item = function(aliasOrSpec)
            return self:Resolve("item", aliasOrSpec)
        end,
        entity = function(aliasOrSpec)
            return self:Resolve("entity", aliasOrSpec)
        end,
        state = {
            snapshot = function(spec)
                return self:SnapshotState(spec)
            end,
            restore = function()
                return self:RestoreState()
            end,
        },
    }
end

return Manager
