local Doubles = {}

local stateByFn = setmetatable({}, {
    __mode = "k",
})

---@param sandbox table
---@param target any
---@return any
local function wrapIfNeeded(sandbox, target)
    if (target == _G.Osi or target == _G.Ext) and target ~= nil then
        if type(sandbox) ~= "table" or type(sandbox.TrackRestore) ~= "function" then
            error("Cannot wrap Ext/Osi without a valid sandbox context", 3)
        end
        local name = (target == _G.Osi) and "Osi" or "Ext"
        sandbox._wrappers = sandbox._wrappers or {}
        if not sandbox._wrappers[name] then
            local original = target
            local wrapper = setmetatable({}, {
                __index = function(_, key)
                    local val = original[key]
                    if type(val) == "function" or type(val) == "userdata" then
                        -- Bind it to the wrapper so that when called, it doesn't get messed up?
                        -- Actually, the original is just Osi, so methods on original don't need re-binding.
                        return val
                    end
                    return val
                end,
                __newindex = function(_, key, value)
                    -- Don't allow writing directly to Osi inside the catch-all, but we just pass it
                    original[key] = value
                end
            })
            sandbox._wrappers[name] = wrapper
            _G[name] = wrapper
            sandbox:TrackRestore(function()
                _G[name] = original
            end)
        end
        return sandbox._wrappers[name]
    end
    return target
end

---@param fn function
---@return table|nil
function Doubles.GetState(fn)
    return stateByFn[fn]
end

---@param value any
---@return boolean
function Doubles.IsDouble(value)
    return type(value) == "function" and stateByFn[value] ~= nil
end

---@param impl function|nil
---@return function
function Doubles.CreateMockFn(impl)
    local callback = impl
    if callback ~= nil and type(callback) ~= "function" then
        error("ctx.mockFn([impl]) expects impl to be a function", 2)
    end

    local state = {
        calls = {},
        callCount = 0,
    }

    local mock = function(...)
        state.callCount = state.callCount + 1
        local callArgs = {
            n = select("#", ...),
            ...,
        }
        table.insert(state.calls, callArgs)

        if callback then
            return callback(...)
        end
    end

    stateByFn[mock] = state
    return mock
end

---@param sandbox table
---@param target table
---@param methodName string
---@return function
function Doubles.CreateSpyOn(sandbox, target, methodName)
    if type(target) ~= "table" and type(target) ~= "userdata" then
        error("ctx.spyOn(target, methodName) expects target to be a table or userdata", 2)
    end

    target = wrapIfNeeded(sandbox, target)

    if type(methodName) ~= "string" or methodName == "" then
        error("ctx.spyOn(target, methodName) expects a non-empty methodName", 2)
    end

    local original = target[methodName]
    if type(original) ~= "function" and type(original) ~= "userdata" then
        error("ctx.spyOn(target, methodName) requires an existing function", 2)
    end

    local spy = Doubles.CreateMockFn(function(...)
        return original(...)
    end)

    target[methodName] = spy
    if type(sandbox) == "table" and type(sandbox.TrackRestore) == "function" then
        sandbox:TrackRestore(function()
            target[methodName] = original
        end)
    end

    return spy
end

---@param sandbox table
---@param target table
---@param methodName string
---@param impl function
---@return function
function Doubles.CreateStub(sandbox, target, methodName, impl)
    if type(target) ~= "table" and type(target) ~= "userdata" then
        error("ctx.stub(target, methodName, impl) expects target to be a table or userdata", 2)
    end

    target = wrapIfNeeded(sandbox, target)

    if type(methodName) ~= "string" or methodName == "" then
        error("ctx.stub(target, methodName, impl) expects a non-empty methodName", 2)
    end

    if type(impl) ~= "function" then
        error("ctx.stub(target, methodName, impl) expects impl to be a function", 2)
    end

    local original = target[methodName]
    if type(original) ~= "function" and type(original) ~= "userdata" then
        error("ctx.stub(target, methodName, impl) requires an existing function", 2)
    end

    local stub = Doubles.CreateMockFn(impl)
    target[methodName] = stub

    if type(sandbox) == "table" and type(sandbox.TrackRestore) == "function" then
        sandbox:TrackRestore(function()
            target[methodName] = original
        end)
    end

    return stub
end

return Doubles
