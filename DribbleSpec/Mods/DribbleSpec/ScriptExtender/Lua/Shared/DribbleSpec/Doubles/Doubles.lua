local Doubles = {}

local stateByFn = setmetatable({}, {
    __mode = "k",
})

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
    if type(target) ~= "table" then
        error("ctx.spyOn(target, methodName) expects target to be a table", 2)
    end

    if type(methodName) ~= "string" or methodName == "" then
        error("ctx.spyOn(target, methodName) expects a non-empty methodName", 2)
    end

    local original = target[methodName]
    if type(original) ~= "function" then
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
    if type(target) ~= "table" then
        error("ctx.stub(target, methodName, impl) expects target to be a table", 2)
    end

    if type(methodName) ~= "string" or methodName == "" then
        error("ctx.stub(target, methodName, impl) expects a non-empty methodName", 2)
    end

    if type(impl) ~= "function" then
        error("ctx.stub(target, methodName, impl) expects impl to be a function", 2)
    end

    local original = target[methodName]
    if type(original) ~= "function" then
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
