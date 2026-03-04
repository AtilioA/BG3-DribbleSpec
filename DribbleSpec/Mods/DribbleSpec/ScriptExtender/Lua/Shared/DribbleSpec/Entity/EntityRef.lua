---@class DribbleEntityRef
---@field __dribbleEntityRef boolean
---@field private _guid string|nil
---@field private _netId number|nil
---@field private _resolver function|nil
local EntityRef = {}
EntityRef.__index = EntityRef

---@param entity any
---@param key string
---@return any
local function readField(entity, key)
    local ok, value = pcall(function()
        return entity[key]
    end)
    if ok then
        return value
    end

    return nil
end

---@param entity any
---@param methodName string
---@return boolean
local function hasMethod(entity, methodName)
    local candidate = readField(entity, methodName)
    return type(candidate) == "function"
end

---@param value any
---@return boolean
local function isEntityLike(value)
    local valueType = type(value)
    if valueType ~= "userdata" and valueType ~= "table" then
        return false
    end

    return hasMethod(value, "GetComponent") or hasMethod(value, "GetAllComponents")
end

---@param value any
---@return string|nil
local function readGuid(value)
    if type(value) ~= "table" and type(value) ~= "userdata" then
        return nil
    end

    local guid = readField(value, "Guid")
    if type(guid) == "string" and guid ~= "" then
        return guid
    end

    local guidUpper = readField(value, "GUID")
    if type(guidUpper) == "string" and guidUpper ~= "" then
        return guidUpper
    end

    return nil
end

---@param value any
---@return number|nil
local function readNetId(value)
    if type(value) ~= "table" and type(value) ~= "userdata" then
        return nil
    end

    local netId = readField(value, "NetId")
    if type(netId) == "number" then
        return netId
    end

    local netIdUpper = readField(value, "NetID")
    if type(netIdUpper) == "number" then
        return netIdUpper
    end

    return nil
end

---@param source any
---@return string|nil, number|nil, function|nil
local function normalizeSource(source)
    local sourceType = type(source)
    if sourceType == "string" then
        return source, nil, nil
    end

    if sourceType == "number" then
        return nil, source, nil
    end

    if sourceType == "function" then
        return nil, nil, source
    end

    if sourceType == "table" then
        local guid = source.guid or source.Guid or source.uuid or source.UUID or source.entityGuid
        if type(guid) ~= "string" or guid == "" then
            guid = nil
        end

        local netId = source.netId or source.NetId
        if type(netId) ~= "number" then
            netId = nil
        end

        local resolver = nil
        if type(source.resolve) == "function" then
            resolver = function()
                return source.resolve(source)
            end
        elseif type(source.Resolve) == "function" then
            resolver = function()
                return source:Resolve()
            end
        elseif source.value ~= nil then
            resolver = function()
                return source.value
            end
        end

        return guid, netId, resolver
    end

    if sourceType == "userdata" then
        return nil, nil, function()
            return source
        end
    end

    return nil, nil, nil
end

---@param source any
---@return DribbleEntityRef
function EntityRef.Create(source)
    if type(source) == "table" and source.__dribbleEntityRef == true and type(source.Resolve) == "function" then
        return source
    end

    local guid, netId, resolver = normalizeSource(source)

    return setmetatable({
        __dribbleEntityRef = true,
        _guid = guid,
        _netId = netId,
        _resolver = resolver,
    }, EntityRef)
end

---@return any
function EntityRef:Resolve()
    if type(self._resolver) == "function" then
        local ok, value = pcall(self._resolver)
        if ok and value ~= nil then
            return value
        end
    end

    if type(self._guid) == "string" and self._guid ~= "" then
        local ok, value = pcall(Ext.Entity.Get, self._guid)
        if ok and value ~= nil then
            return value
        end
    end

    if type(self._netId) == "number" then
        local ok, value = pcall(Ext.Entity.Get, self._netId)
        if ok and value ~= nil then
            return value
        end
    end

    return nil
end

---@return string|nil
function EntityRef:GetGuid()
    if type(self._guid) == "string" and self._guid ~= "" then
        return self._guid
    end

    local resolved = self:Resolve()
    return readGuid(resolved)
end

---@return number|nil
function EntityRef:GetNetId()
    if type(self._netId) == "number" then
        return self._netId
    end

    local resolved = self:Resolve()
    return readNetId(resolved)
end

---@return boolean
function EntityRef:IsEntityRef()
    return true
end

---@param source any
---@return DribbleEntityRef|nil
function EntityRef.TryCreate(source)
    if source == nil then
        return nil
    end

    local ref = EntityRef.Create(source)
    if type(ref._guid) == "string" and ref._guid ~= "" then
        return ref
    end

    if type(ref._netId) == "number" then
        return ref
    end

    local resolved = ref:Resolve()
    if isEntityLike(resolved) then
        return ref
    end

    return nil
end

---@param value any
---@return boolean
function EntityRef.IsEntityLike(value)
    return isEntityLike(value)
end

return EntityRef
