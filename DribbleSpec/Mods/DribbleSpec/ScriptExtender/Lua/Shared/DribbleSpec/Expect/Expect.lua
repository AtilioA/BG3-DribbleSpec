local Expect = {}
local Format = Ext.Require("Shared/DribbleSpec/Expect/Format.lua")
local DeepEqual = Ext.Require("Shared/DribbleSpec/Expect/DeepEqual.lua")
local Diff = Ext.Require("Shared/DribbleSpec/Expect/Diff.lua")
local Doubles = Ext.Require("Shared/DribbleSpec/Doubles/Doubles.lua")
local EntityRef = Ext.Require("Shared/DribbleSpec/Entity/EntityRef.lua")
local VolatileFilters = Ext.Require("Shared/DribbleSpec/Expect/VolatileFilters.lua")

local GUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

---@type fun(event: table)|nil
local assertionObserver = nil

---@param value any
---@return string
local renderValue

---@param matcherName string
---@param message string
local function fail(matcherName, message)
    error(string.format("expect.%s failed: %s", tostring(matcherName), tostring(message)), 3)
end

---@param observer fun(event: table)|nil
function Expect.SetAssertionObserver(observer)
    if observer ~= nil and type(observer) ~= "function" then
        error("Expect.SetAssertionObserver(observer) requires a function or nil", 2)
    end

    assertionObserver = observer
end

---@param event table
local function emitAssertion(event)
    if type(assertionObserver) ~= "function" then
        return
    end

    pcall(assertionObserver, event)
end

---@param matcherName string
---@param actual any
---@param matcher function
---@return function
local function wrapMatcher(matcherName, actual, matcher)
    return function(...)
        if type(assertionObserver) ~= "function" then
            return matcher(...)
        end

        local argCount = select("#", ...)
        local args = { ... }
        local expected = nil
        if argCount > 0 then
            expected = renderValue(args[1])
        end

        local ok, err = pcall(function()
            matcher(table.unpack(args, 1, argCount))
        end)
        if ok then
            emitAssertion({
                matcher = matcherName,
                status = "passed",
                actual = renderValue(actual),
                expected = expected,
            })
            return
        end

        emitAssertion({
            matcher = matcherName,
            status = "failed",
            actual = renderValue(actual),
            expected = expected,
            error = tostring(err),
        })
        error(err, 0)
    end
end

---@param value any
---@return string
renderValue = function(value)
    return Format.Value(value)
end

---@param haystack any
---@param needle any
---@return boolean
local function arrayContains(haystack, needle)
    for i = 1, #haystack do
        local equal = DeepEqual.Compare(needle, haystack[i])
        if equal then
            return true
        end
    end

    return false
end

---@param fn any
---@return boolean, string
local function captureThrownError(fn)
    if type(fn) ~= "function" then
        return false, "value must be a function"
    end

    local ok, err = xpcall(function()
        fn()
    end, debug.traceback)

    if ok then
        return false, "function did not throw"
    end

    return true, tostring(err)
end

---@param value any
---@param matcherName string
---@return table
local function requireDoubleState(value, matcherName)
    if not Doubles.IsDouble(value) then
        fail(matcherName, "value is not a mock/spy function")
    end

    local state = Doubles.GetState(value)
    if type(state) ~= "table" then
        fail(matcherName, "value is not a mock/spy function")
    end

    return state
end

---@param state table
---@param expectedArgs table
---@return boolean
local function hasCallWithExactArgs(state, expectedArgs)
    local calls = state.calls or {}
    for _, callArgs in ipairs(calls) do
        if (callArgs.n or 0) == (expectedArgs.n or 0) then
            local allMatch = true
            for i = 1, expectedArgs.n do
                local equal = DeepEqual.Compare(expectedArgs[i], callArgs[i])
                if not equal then
                    allMatch = false
                    break
                end
            end

            if allMatch then
                return true
            end
        end
    end

    return false
end

---@param subset any
---@param candidate any
---@return boolean
local function isSubsetMatch(subset, candidate)
    if type(subset) ~= "table" then
        local equal = DeepEqual.Compare(subset, candidate)
        return equal == true
    end

    if type(candidate) ~= "table" then
        return false
    end

    for key, subsetValue in pairs(subset) do
        if candidate[key] == nil then
            return false
        end

        if not isSubsetMatch(subsetValue, candidate[key]) then
            return false
        end
    end

    return true
end

---@param state table
---@param subset table
---@return boolean
local function hasCallWithSubsetTable(state, subset)
    local calls = state.calls or {}
    for _, callArgs in ipairs(calls) do
        local argCount = callArgs.n or 0
        for i = 1, argCount do
            if type(callArgs[i]) == "table" and isSubsetMatch(subset, callArgs[i]) then
                return true
            end
        end
    end

    return false
end

---@param value any
---@return boolean
local function isGuid(value)
    return type(value) == "string" and string.match(value, GUID_PATTERN) ~= nil
end

---@param value any
---@return any|nil, string|nil
local function resolveFromEntityRef(value)
    if type(value) ~= "table" then
        return nil, nil
    end

    local ref = value
    if not (value.__dribbleEntityRef == true and type(value.Resolve) == "function") then
        if type(value.ref) == "table" and value.ref.__dribbleEntityRef == true and type(value.ref.Resolve) == "function" then
            ref = value.ref
        else
            return nil, nil
        end
    end

    local ok, resolvedOrErr = pcall(ref.Resolve, ref)
    if not ok then
        return nil, tostring(resolvedOrErr)
    end

    if resolvedOrErr == nil then
        return nil, "entity reference could not be resolved"
    end

    return resolvedOrErr, nil
end

---@param value any
---@return any|nil, string|nil
local function resolveEntityCandidate(value)
    local resolvedFromRef, refErr = resolveFromEntityRef(value)
    if resolvedFromRef ~= nil then
        if EntityRef.IsEntityLike(resolvedFromRef) then
            return resolvedFromRef, nil
        end

        return nil, "resolved value is not an entity"
    end

    if refErr ~= nil then
        return nil, refErr
    end

    if EntityRef.IsEntityLike(value) then
        return value, nil
    end

    local inferredRef = EntityRef.TryCreate(value)
    if inferredRef ~= nil then
        local resolved = inferredRef:Resolve()
        if EntityRef.IsEntityLike(resolved) then
            return resolved, nil
        end

        return nil, "entity reference could not be resolved"
    end

    return nil, "value is not an entity or entity reference"
end

---@param entity any
---@param componentName string
---@return any
local function readComponent(entity, componentName)
    local getComponent = nil
    local okMethod, methodOrErr = pcall(function()
        return entity.GetComponent
    end)
    if okMethod and type(methodOrErr) == "function" then
        getComponent = methodOrErr
    end

    if type(getComponent) == "function" then
        local okCall, valueOrErr = pcall(getComponent, entity, componentName)
        if okCall then
            return valueOrErr
        end
    end

    local okAll, allOrErr = pcall(function()
        return entity.GetAllComponents
    end)
    if okAll and type(allOrErr) == "function" then
        local okComponents, componentsOrErr = pcall(allOrErr, entity)
        if okComponents and type(componentsOrErr) == "table" then
            local component = componentsOrErr[componentName]
            if component ~= nil then
                return component
            end
        end
    end

    local okIndex, valueOrErr = pcall(function()
        return entity[componentName]
    end)
    if okIndex then
        return valueOrErr
    end

    return nil
end

---@param actual any
---@return table
function Expect.Create(actual)
    local matchers = {
        toBe = function(expected)
            if actual ~= expected then
                fail("toBe", string.format("expected=%s actual=%s", tostring(expected), tostring(actual)))
            end
        end,
        toBeNil = function()
            if actual ~= nil then
                fail("toBeNil", string.format("expected nil, actual=%s", renderValue(actual)))
            end
        end,
        toBeTruthy = function()
            if not actual then
                fail("toBeTruthy", string.format("expected truthy value, actual=%s", renderValue(actual)))
            end
        end,
        toBeFalsy = function()
            if actual ~= nil and actual ~= false then
                fail("toBeFalsy", string.format("expected falsy value, actual=%s", renderValue(actual)))
            end
        end,
        toContain = function(needle)
            if type(actual) == "string" then
                local token = tostring(needle)
                if string.find(actual, token, 1, true) == nil then
                    fail("toContain", string.format("expected string to contain '%s'", token))
                end
                return
            end

            if type(actual) == "table" then
                if not arrayContains(actual, needle) then
                    fail("toContain", string.format("expected array table to contain %s", renderValue(needle)))
                end
                return
            end

            fail("toContain", string.format("unsupported container type '%s'", type(actual)))
        end,
        toEqual = function(expected, options)
            if options ~= nil and type(options) ~= "table" then
                fail("toEqual", "options must be a table when provided")
            end

            local expectedValue = expected
            local actualValue = actual
            if type(options) == "table" and options.volatilePreset ~= nil then
                local okExpected, filteredExpectedOrErr = pcall(VolatileFilters.ApplyPreset, expectedValue,
                    options.volatilePreset)
                if not okExpected then
                    fail("toEqual", tostring(filteredExpectedOrErr))
                end

                local okActual, filteredActualOrErr = pcall(VolatileFilters.ApplyPreset, actualValue,
                    options.volatilePreset)
                if not okActual then
                    fail("toEqual", tostring(filteredActualOrErr))
                end

                expectedValue = filteredExpectedOrErr
                actualValue = filteredActualOrErr
            end

            local equal, detail = DeepEqual.Compare(expectedValue, actualValue)
            if not equal then
                fail("toEqual", Diff.FromMismatch(detail))
            end
        end,
        toBeGuid = function()
            if not isGuid(actual) then
                fail("toBeGuid", string.format("expected GUID string, actual=%s", renderValue(actual)))
            end
        end,
        toBeEntity = function()
            local entity, reason = resolveEntityCandidate(actual)
            if entity == nil then
                fail("toBeEntity", tostring(reason or "value is not an entity"))
            end
        end,
        toHaveComponent = function(componentName)
            if type(componentName) ~= "string" or componentName == "" then
                fail("toHaveComponent", "component name must be a non-empty string")
            end

            local entity, reason = resolveEntityCandidate(actual)
            if entity == nil then
                fail("toHaveComponent", tostring(reason or "value is not an entity"))
            end

            local component = readComponent(entity, componentName)
            if component == nil then
                fail("toHaveComponent", string.format("component '%s' was not found", componentName))
            end
        end,
        toHaveBeenCalled = function()
            local state = requireDoubleState(actual, "toHaveBeenCalled")
            if (state.callCount or 0) < 1 then
                fail("toHaveBeenCalled", "expected function to be called at least once")
            end
        end,
        toHaveBeenCalledTimes = function(expectedCount)
            if type(expectedCount) ~= "number" then
                fail("toHaveBeenCalledTimes", "expected call count must be a number")
            end

            local state = requireDoubleState(actual, "toHaveBeenCalledTimes")
            local callCount = state.callCount or 0
            if callCount ~= expectedCount then
                fail("toHaveBeenCalledTimes", string.format("expected=%s actual=%s", tostring(expectedCount),
                    tostring(callCount)))
            end
        end,
        toHaveBeenCalledWith = function(...)
            local state = requireDoubleState(actual, "toHaveBeenCalledWith")
            local expectedArgs = {
                n = select("#", ...),
                ...,
            }
            if not hasCallWithExactArgs(state, expectedArgs) then
                fail("toHaveBeenCalledWith", "no recorded call matched expected arguments")
            end
        end,
        toHaveBeenCalledWithMatch = function(expectedSubset)
            if type(expectedSubset) ~= "table" then
                fail("toHaveBeenCalledWithMatch", "expected subset must be a table")
            end

            local state = requireDoubleState(actual, "toHaveBeenCalledWithMatch")
            if not hasCallWithSubsetTable(state, expectedSubset) then
                fail("toHaveBeenCalledWithMatch", "no table argument matched expected subset")
            end
        end,
        toThrow = function()
            local thrown, message = captureThrownError(actual)
            if not thrown then
                fail("toThrow", message)
            end
        end,
        toThrowMatch = function(pattern)
            local thrown, message = captureThrownError(actual)
            if not thrown then
                fail("toThrowMatch", message)
            end

            local normalizedPattern = tostring(pattern or "")
            if normalizedPattern == "" then
                fail("toThrowMatch", "pattern must be a non-empty Lua pattern")
            end

            if not string.match(message, normalizedPattern) then
                fail("toThrowMatch",
                    string.format("error '%s' does not match Lua pattern '%s'", message, normalizedPattern))
            end
        end,
    }

    for matcherName, matcher in pairs(matchers) do
        if type(matcher) == "function" then
            matchers[matcherName] = wrapMatcher(matcherName, actual, matcher)
        end
    end

    return matchers
end

---@param actual any
---@return table
function Expect.Expect(actual)
    return Expect.Create(actual)
end

return Expect
