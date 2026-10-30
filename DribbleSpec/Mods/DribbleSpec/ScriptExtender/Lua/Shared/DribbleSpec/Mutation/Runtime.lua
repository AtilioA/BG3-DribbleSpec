-- Mutation runtime (`__M` in patch chunks): active mutant switch, hit recording, step limit.
-- Pure Lua: no Ext, io, os, or package, so the host tests load this same file.

---@class MutationRuntime
---@field a integer active mutant id, 0 = none
---@field hits table<integer, true>|nil nil = coverage off
---@field steps integer
---@field stepLimit integer
---@field deadlineMs number|nil compared against clock()
---@field clock (fun(): number)|nil returns milliseconds
---@field limitHit "steps"|"time"|nil sticky until the agent clears it
local R = { a = 0, hits = nil, steps = 0, stepLimit = math.maxinteger, deadlineMs = nil, clock = nil, limitHit = nil }

local DEADLINE_CHECK_INTERVAL = 1000

-- Replacements per relational operator: mutant `id` takes [1], `id + 1` takes [2].
local RELATIONAL = {
    ["<"] = { "<=", ">=" },
    ["<="] = { "<", ">" },
    [">"] = { ">=", "<=" },
    [">="] = { ">", "<" },
}

-- Applies `op` literally so metamethod dispatch matches the original expression.
local function compare(op, a, b)
    if op == "<" then return a < b end
    if op == "<=" then return a <= b end
    if op == ">" then return a > b end
    return a >= b
end

--- Records hits for ids `id .. id + count - 1` while coverage is on.
---@param id integer
---@param count integer
function R.Hit(id, count)
    local hits = R.hits
    if hits == nil then return end
    for i = id, id + count - 1 do
        hits[i] = true
    end
end

--- Counts a step; raises only while a mutant is active and a limit is reached.
function R.S()
    R.steps = R.steps + 1
    if R.a == 0 then return end
    if R.limitHit == nil then
        if R.steps > R.stepLimit then
            R.limitHit = "steps"
        elseif R.clock ~= nil and R.deadlineMs ~= nil and R.steps % DEADLINE_CHECK_INTERVAL == 0
            and R.clock() > R.deadlineMs then
            R.limitHit = "time"
        end
    end
    if R.limitHit ~= nil then
        error("DribbleSpecMutation: limit", 2)
    end
end

--- Relational mutation site; `id` and `id + 1` are its two mutants.
---@param id integer
---@param op "<"|"<="|">"|">="
---@param a any
---@param b any
---@return boolean
function R.Cmp(id, op, a, b)
    local alt = RELATIONAL[op]
    R.Hit(id, 2)
    local active = R.a
    if active == id then
        op = alt[1]
    elseif active == id + 1 then
        op = alt[2]
    end
    return compare(op, a, b)
end

return R
