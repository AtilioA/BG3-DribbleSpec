---@class DribblePublicSymbolDefinition
---@field name string
---@field resolver fun(api: table): any

local PublicSymbols = {}

---@type DribblePublicSymbolDefinition[]
local SYMBOL_DEFINITIONS = {
    {
        name = "RegisterTestGlobals",
        resolver = function(api)
            return api.RegisterTestGlobals
        end,
    },
    {
        name = "describe",
        resolver = function(api)
            return api.describe
        end,
    },
    {
        name = "test",
        resolver = function(api)
            return api.test
        end,
    },
    {
        name = "it",
        resolver = function(api)
            return api.it
        end,
    },
    {
        name = "beforeAll",
        resolver = function(api)
            return api.beforeAll
        end,
    },
    {
        name = "beforeEach",
        resolver = function(api)
            return api.beforeEach
        end,
    },
    {
        name = "afterEach",
        resolver = function(api)
            return api.afterEach
        end,
    },
    {
        name = "afterAll",
        resolver = function(api)
            return api.afterAll
        end,
    },
    {
        name = "expect",
        resolver = function(api)
            return api.expect
        end,
    },
    {
        name = "entityRef",
        resolver = function(api)
            return api.entityRef
        end,
    },
    {
        name = "Run",
        resolver = function(api)
            return api.Run
        end,
    },
    {
        name = "RunFromArgs",
        resolver = function(api)
            return api.RunFromArgs
        end,
    },
}

---@return string[]
function PublicSymbols.Keys()
    local keys = {}
    for index, definition in ipairs(SYMBOL_DEFINITIONS) do
        keys[index] = definition.name
    end

    return keys
end

---@param api table
---@return table<string, any>
function PublicSymbols.Resolve(api)
    if type(api) ~= "table" then
        error("PublicSymbols.Resolve(api) requires a table", 2)
    end

    local symbols = {}
    for _, definition in ipairs(SYMBOL_DEFINITIONS) do
        local value = definition.resolver(api)
        if value ~= nil then
            symbols[definition.name] = value
        end
    end

    return symbols
end

return PublicSymbols
