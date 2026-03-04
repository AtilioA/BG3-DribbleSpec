local PreplacedProvider = {}
PreplacedProvider.__index = PreplacedProvider

---@param source table
---@return table
local function shallowCopy(source)
    local clone = {}
    for k, v in pairs(source or {}) do
        clone[k] = v
    end

    return clone
end

---@param base table|nil
---@param overrides table|nil
---@return table
local function mergeDescriptors(base, overrides)
    local merged = shallowCopy(base or {})
    for k, v in pairs(overrides or {}) do
        merged[k] = v
    end

    return merged
end

---@param aliases table
---@param kind string
---@param alias string
---@return table|nil
local function resolveAliasDescriptor(aliases, kind, alias)
    if type(aliases) ~= "table" then
        return nil
    end

    if type(aliases[kind]) == "table" and type(aliases[kind][alias]) == "table" then
        return aliases[kind][alias]
    end

    if type(aliases.shared) == "table" and type(aliases.shared[alias]) == "table" then
        return aliases.shared[alias]
    end

    if type(aliases[alias]) == "table" then
        return aliases[alias]
    end

    return nil
end

---@param descriptor table
---@param context table
---@return any
local function resolveValue(descriptor, context)
    if type(descriptor.resolve) == "function" then
        return descriptor.resolve(descriptor, context)
    end

    if type(descriptor.get) == "function" then
        return descriptor.get(descriptor, context)
    end

    local guid = descriptor.guid or descriptor.uuid or descriptor.entityGuid
    if type(guid) == "string" and guid ~= "" then
        return Ext.Entity.Get(guid)
    end

    local netId = descriptor.netId
    if type(netId) == "number" then
        return Ext.Entity.Get(netId)
    end

    if descriptor.value ~= nil then
        return descriptor.value
    end

    return nil
end

---@param params table|nil
---@return table
function PreplacedProvider.Create(params)
    local resolvedParams = params or {}

    return setmetatable({
        name = "preplaced",
        _aliases = resolvedParams.aliases or {},
    }, PreplacedProvider)
end

---@param kind string
---@param spec table
---@param context table
---@return table|nil, string|nil
function PreplacedProvider:Resolve(kind, spec, context)
    if type(spec) ~= "table" then
        return nil, nil
    end

    local descriptor = spec
    local alias = spec.alias
    if type(alias) == "string" and alias ~= "" then
        local aliasDescriptor = resolveAliasDescriptor(self._aliases, kind, alias)
        if type(aliasDescriptor) == "table" then
            descriptor = mergeDescriptors(aliasDescriptor, spec)
        end
    end

    local ok, resolvedOrErr = pcall(resolveValue, descriptor, context)
    if not ok then
        return nil, tostring(resolvedOrErr)
    end

    if resolvedOrErr == nil then
        return nil, nil
    end

    return {
        value = resolvedOrErr,
        guid = descriptor.guid or descriptor.uuid or descriptor.entityGuid,
        netId = descriptor.netId,
        teardown = descriptor.cleanup,
    }, nil
end

return PreplacedProvider
