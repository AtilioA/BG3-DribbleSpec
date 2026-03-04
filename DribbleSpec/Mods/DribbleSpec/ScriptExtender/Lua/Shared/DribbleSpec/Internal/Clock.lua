local Clock = {}

---@return integer
function Clock.NowMs()
    return math.floor(Ext.Timer.ClockEpoch() * 1000)
end

return Clock
