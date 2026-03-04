local SkipSignal = Ext.Require("Shared/DribbleSpec/Runtime/SkipSignal.lua")

local Helpers = {}

---@class DribbleSpecRuntimeHelpersParams
---@field context string|nil
---@field options table|nil
---@field tickDriver function|nil

---@param runContext string
---@param options table|nil
---@return string
local function resolveContext(runContext, options)
    if type(options) == "table" then
        local optionContext = string.lower(tostring(options.context or ""))
        if optionContext == "client" or optionContext == "server" then
            return optionContext
        end
    end

    if runContext == "client" or runContext == "server" then
        return runContext
    end

    return "unknown"
end

---@return function|nil
local function resolveOnNextTick()
    return Ext.OnNextTick
end

---@return function|nil
local function resolveWaitFor()
    return Ext.Timer.WaitFor
end

---@param params DribbleSpecRuntimeHelpersParams|nil
---@return table
function Helpers.Create(params)
    local resolvedParams = params or {}
    local context = resolveContext(resolvedParams.context, resolvedParams.options)
    local virtualTicks = 0
    local tickDriver = type(resolvedParams.tickDriver) == "function" and resolvedParams.tickDriver or nil

    local function tryScheduleEngineTick()
        local onNextTick = resolveOnNextTick()
        if onNextTick then
            local scheduled = pcall(onNextTick, function() end)
            if scheduled then
                return true
            end
        end

        local waitFor = resolveWaitFor()
        if waitFor then
            local scheduled = pcall(waitFor, 0, function() end)
            if scheduled then
                return true
            end
        end

        return false
    end

    local function nextTick()
        if tickDriver then
            local ok, advanced = pcall(tickDriver)
            if ok and advanced == true then
                return
            end
        end

        if tryScheduleEngineTick() then
            virtualTicks = virtualTicks + 1
            return
        end

        virtualTicks = virtualTicks + 1
    end

    ---@param predicate function
    ---@param opts table
    local function waitUntil(predicate, opts)
        if type(predicate) ~= "function" then
            error("ctx.waitUntil(predicate, opts) expects predicate to be a function", 2)
        end

        if type(opts) ~= "table" then
            error("ctx.waitUntil(predicate, opts) requires opts.timeoutTicks", 2)
        end

        local timeoutTicks = opts.timeoutTicks
        if type(timeoutTicks) ~= "number" or timeoutTicks < 1 or timeoutTicks ~= math.floor(timeoutTicks) then
            error("ctx.waitUntil(predicate, opts) requires opts.timeoutTicks as positive integer", 2)
        end

        for tick = 0, timeoutTicks do
            if predicate() then
                return true, tick
            end

            if tick < timeoutTicks then
                nextTick()
            end
        end

        error(string.format("ctx.waitUntil timed out after %d ticks", timeoutTicks), 2)
    end

    return {
        requireClient = function()
            if context ~= "client" then
                SkipSignal.Throw("Requires client context")
            end
        end,
        requireServer = function()
            if context ~= "server" then
                SkipSignal.Throw("Requires server context")
            end
        end,
        nextTick = nextTick,
        waitUntil = waitUntil,
    }
end

return Helpers
