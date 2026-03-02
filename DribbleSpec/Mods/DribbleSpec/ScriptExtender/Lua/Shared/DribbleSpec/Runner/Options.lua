local Options = {}

Options.DEFAULT_MANIFEST_PATH = "DribbleTests.lua"

---@param options table|nil
---@return table
function Options.Normalize(options)
    local normalized = options or {}

    if type(normalized.tags) ~= "table" then
        normalized.tags = {}
    end

    if type(normalized.context) ~= "string" or normalized.context == "" then
        normalized.context = "any"
    else
        normalized.context = string.lower(normalized.context)
    end

    normalized.failFast = normalized.failFast == true
    normalized.help = normalized.help == true
    normalized.manifestPath = normalized.manifestPath or Options.DEFAULT_MANIFEST_PATH
    normalized.unknownArgs = normalized.unknownArgs or {}

    return normalized
end

---@param args any[]
---@return table
function Options.ParseArgs(args)
    local options = Options.Normalize({
        tags = {},
        unknownArgs = {},
    })

    local i = 1
    if type(args[1]) == "string" and string.lower(args[1]) == "dribble" then
        i = 2
    end

    while i <= #args do
        local token = tostring(args[i])

        if token == "--help" or token == "-h" then
            options.help = true
        elseif token == "--fail-fast" then
            options.failFast = true
        elseif token == "--name" then
            options.namePattern = tostring(args[i + 1] or "")
            i = i + 1
        elseif token == "--tag" then
            local tag = tostring(args[i + 1] or "")
            if tag ~= "" then
                table.insert(options.tags, tag)
            end
            i = i + 1
        elseif token == "--context" then
            options.context = string.lower(tostring(args[i + 1] or "any"))
            i = i + 1
        elseif token == "--manifest" then
            options.manifestPath = tostring(args[i + 1] or Options.DEFAULT_MANIFEST_PATH)
            i = i + 1
        elseif token == "--mod-uuid" then
            options.callerModuleUUID = tostring(args[i + 1] or "")
            i = i + 1
        elseif token == "--json-out" then
            options.jsonOut = tostring(args[i + 1] or "")
            i = i + 1
        else
            table.insert(options.unknownArgs, token)
        end

        i = i + 1
    end

    return Options.Normalize(options)
end

return Options
