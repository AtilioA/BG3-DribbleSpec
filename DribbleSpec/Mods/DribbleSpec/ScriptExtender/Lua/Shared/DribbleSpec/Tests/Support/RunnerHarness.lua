local Registry = Ext.Require("Shared/DribbleSpec/Core/Registry.lua")
local Runner = Ext.Require("Shared/DribbleSpec/Runner/Runner.lua")

local Harness = {}

local function resolveMetadataAndCallback(optionsOrCallback, maybeCallback, callsite)
    if type(optionsOrCallback) == "function" and maybeCallback == nil then
        return {}, optionsOrCallback
    end

    if type(optionsOrCallback) == "table" and type(maybeCallback) == "function" then
        return optionsOrCallback, maybeCallback
    end

    error(string.format("%s() expects (name, callback) or (name, options, callback)", callsite), 3)
end

local function createDsl(registry)
    local dsl = {}

    local function registerTest(name, optionsOrCallback, maybeCallback, metadataPatch)
        local metadata, callback = resolveMetadataAndCallback(optionsOrCallback, maybeCallback, "test")
        if metadataPatch then
            for k, v in pairs(metadataPatch) do
                metadata[k] = v
            end
        end

        return registry:AddTest(name, metadata, callback)
    end

    function dsl.describe(name, optionsOrCallback, maybeCallback)
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

    dsl.test = setmetatable({
        skip = testSkip,
        only = testOnly,
    }, {
        __call = function(_, name, optionsOrCallback, maybeCallback)
            return testMain(name, optionsOrCallback, maybeCallback)
        end,
    })

    dsl.it = dsl.test
    dsl.beforeAll = function(callback)
        return registry:AddHook("beforeAll", callback)
    end
    dsl.beforeEach = function(callback)
        return registry:AddHook("beforeEach", callback)
    end
    dsl.afterEach = function(callback)
        return registry:AddHook("afterEach", callback)
    end
    dsl.afterAll = function(callback)
        return registry:AddHook("afterAll", callback)
    end

    return dsl
end

---@param registerFn fun(dsl: table)
---@param options table|nil
---@return table
function Harness.Run(registerFn, options)
    local registry = Registry.Create()
    local dsl = createDsl(registry)
    registerFn(dsl)

    return Runner.Run({
        registry = registry,
        options = options or {},
        clock = {
            NowMs = function()
                return 0
            end,
        },
    })
end

return Harness
