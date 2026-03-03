local ApiBinder = {}

---@param optionsOrCallback table|function|nil
---@param maybeCallback function|nil
---@param callsite string
---@return table, function
local function resolveMetadataAndCallback(optionsOrCallback, maybeCallback, callsite)
    if type(optionsOrCallback) == "function" and maybeCallback == nil then
        return {}, optionsOrCallback
    end

    if type(optionsOrCallback) == "table" and type(maybeCallback) == "function" then
        return optionsOrCallback, maybeCallback
    end

    error(string.format("%s() expects (%s, callback) or (%s, options, callback)", callsite, "name", "name"), 3)
end

---@param api table
---@param registry table
---@return table
function ApiBinder.Bind(api, registry)
    local function registerTest(name, optionsOrCallback, maybeCallback, metadataPatch)
        local metadata, callback = resolveMetadataAndCallback(optionsOrCallback, maybeCallback, "test")
        if metadataPatch then
            for k, v in pairs(metadataPatch) do
                metadata[k] = v
            end
        end

        return registry:AddTest(name, metadata, callback)
    end

    ---@param name string
    ---@param optionsOrCallback table|function
    ---@param maybeCallback function|nil
    function api.describe(name, optionsOrCallback, maybeCallback)
        local metadata, callback = resolveMetadataAndCallback(optionsOrCallback, maybeCallback, "describe")
        registry:BeginSuite(name, metadata)

        local ok, err = xpcall(function()
            callback()
        end, debug.traceback)

        registry:EndSuite()
        if not ok then
            error(err, 0)
        end
    end

    local function testMain(name, optionsOrCallback, maybeCallback)
        return registerTest(name, optionsOrCallback, maybeCallback, nil)
    end

    local function testSkip(name, optionsOrCallback, maybeCallback)
        return registerTest(name, optionsOrCallback, maybeCallback, { skip = true })
    end

    local function testOnly(name, optionsOrCallback, maybeCallback)
        return registerTest(name, optionsOrCallback, maybeCallback, { only = true })
    end

    api.test = setmetatable({
        skip = testSkip,
        only = testOnly,
    }, {
        __call = function(_, name, optionsOrCallback, maybeCallback)
            return testMain(name, optionsOrCallback, maybeCallback)
        end,
    })

    api.it = api.test

    ---@param callback function
    function api.beforeAll(callback)
        return registry:AddHook("beforeAll", callback)
    end

    ---@param callback function
    function api.beforeEach(callback)
        return registry:AddHook("beforeEach", callback)
    end

    ---@param callback function
    function api.afterEach(callback)
        return registry:AddHook("afterEach", callback)
    end

    ---@param callback function
    function api.afterAll(callback)
        return registry:AddHook("afterAll", callback)
    end

    return {
        resolveMetadataAndCallback = resolveMetadataAndCallback,
    }
end

return ApiBinder
