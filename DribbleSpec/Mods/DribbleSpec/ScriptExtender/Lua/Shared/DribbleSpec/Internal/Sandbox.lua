---@class DribbleSandbox
---@field private _restorers function[]
local Sandbox = {}
Sandbox.__index = Sandbox

---@return DribbleSandbox
function Sandbox.Create()
    return setmetatable({
        _restorers = {},
    }, Sandbox)
end

---@param restoreFn function
function Sandbox:TrackRestore(restoreFn)
    if type(restoreFn) ~= "function" then
        return
    end

    table.insert(self._restorers, 1, restoreFn)
end

---@return integer restoredCount
function Sandbox:RestoreAll()
    local restoredCount = 0
    for _, restoreFn in ipairs(self._restorers) do
        pcall(restoreFn)
        restoredCount = restoredCount + 1
    end

    self._restorers = {}
    return restoredCount
end

return Sandbox
