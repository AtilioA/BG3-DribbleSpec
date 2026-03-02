local Clock = {}

---@return integer
function Clock.NowMs()
    if type(Ext) == "table" and type(Ext.Utils) == "table" and type(Ext.Utils.MonotonicTime) == "function" then
        local seconds = Ext.Utils.MonotonicTime()
        if type(seconds) == "number" then
            return math.floor(seconds * 1000)
        end
    end

    return math.floor(os.clock() * 1000)
end

return Clock
