local SkipSignal = {}

---@class DribbleSpecSkipSignal
---@field __dribbleSkip boolean
---@field reason string

---@param reason string
---@return DribbleSpecSkipSignal
function SkipSignal.New(reason)
    return {
        __dribbleSkip = true,
        reason = tostring(reason or "Skipped by runtime helper"),
    }
end

---@param reason string
function SkipSignal.Throw(reason)
    error(SkipSignal.New(reason), 2)
end

---@param value any
---@return boolean
function SkipSignal.Is(value)
    return type(value) == "table" and value.__dribbleSkip == true and type(value.reason) == "string"
end

---@param value any
---@return string
function SkipSignal.Reason(value)
    if SkipSignal.Is(value) then
        return value.reason
    end

    return "Skipped by runtime helper"
end

return SkipSignal
