local Options = {}

---@param value string
---@return string
local function stripQuotes(value)
    if type(value) ~= "string" then
        return ""
    end
    local len = #value
    if len >= 2 then
        local first = string.sub(value, 1, 1)
        local last = string.sub(value, len, len)
        if (first == '"' and last == '"') or (first == "'" and last == "'") then
            return string.sub(value, 2, len - 1)
        end
    end
    return value
end

local VALID_CONTEXTS = {
    any = true,
    client = true,
    server = true,
}

local QUIET_THRESHOLD = 100

local HELP_TOPIC_ALIASES = {
    ["help"] = "help",
    ["-h"] = "help",
    ["--help"] = "help",
    ["name"] = "name",
    ["--name"] = "name",
    ["tag"] = "tag",
    ["--tag"] = "tag",
    ["context"] = "context",
    ["--context"] = "context",
    ["fail-fast"] = "fail-fast",
    ["--fail-fast"] = "fail-fast",
    ["failfast"] = "fail-fast",
    ["mod-uuid"] = "mod-uuid",
    ["--mod-uuid"] = "mod-uuid",
    ["moduuid"] = "mod-uuid",
    ["verbose"] = "verbose",
    ["--verbose"] = "verbose",
    ["-v"] = "verbose",
    ["quiet"] = "quiet",
    ["--quiet"] = "quiet",
    ["-q"] = "quiet",
    ["no-quiet"] = "no-quiet",
    ["--no-quiet"] = "no-quiet",
}

---@param topic string|nil
---@return string|nil
local function normalizeHelpTopic(topic)
    if type(topic) ~= "string" then
        return nil
    end

    local normalized = string.lower(topic)
    normalized = string.match(normalized, "^%s*(.-)%s*$")
    if normalized == nil or normalized == "" then
        return nil
    end

    local alias = HELP_TOPIC_ALIASES[normalized]
    if alias then
        return alias
    end

    if string.sub(normalized, 1, 1) == "-" then
        local trimmed = string.gsub(normalized, "^-+", "")
        if trimmed ~= "" then
            return HELP_TOPIC_ALIASES[trimmed] or trimmed
        end
    end

    return normalized
end

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

    if VALID_CONTEXTS[normalized.context] ~= true then
        normalized.context = "any"
    end

    normalized.failFast = normalized.failFast == true
    normalized.verbose = normalized.verbose == true
    normalized.quiet = normalized.quiet == true
    normalized.noQuiet = normalized.noQuiet == true
    normalized.help = normalized.help == true
    normalized.helpTopic = normalizeHelpTopic(normalized.helpTopic)
    if type(normalized.ownerModuleUUID) ~= "string" or normalized.ownerModuleUUID == "" then
        normalized.ownerModuleUUID = nil
    end
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
    if type(args[1]) == "string" then
        local commandName = string.lower(args[1])
        if commandName == "dribbles" or commandName == "d" then
            i = 2
        end
    end

    while i <= #args do
        local token = tostring(args[i])

        if token == "--help" or token == "-h" then
            options.help = true
            local topic = normalizeHelpTopic(args[i + 1])
            if topic ~= nil and topic ~= "help" then
                options.helpTopic = topic
                i = i + 1
            end
        elseif token == "--fail-fast" then
            options.failFast = true
        elseif token == "--verbose" or token == "-v" then
            options.verbose = true
        elseif token == "--quiet" or token == "-q" then
            options.quiet = true
        elseif token == "--no-quiet" then
            options.noQuiet = true
        elseif token == "--name" then
            options.namePattern = stripQuotes(tostring(args[i + 1] or ""))
            i = i + 1
        elseif token == "--tag" then
            local tag = stripQuotes(tostring(args[i + 1] or ""))
            if tag ~= "" then
                table.insert(options.tags, tag)
            end
            i = i + 1
        elseif token == "--context" then
            options.context = string.lower(stripQuotes(tostring(args[i + 1] or "any")))
            i = i + 1
        elseif token == "--mod-uuid" then
            options.ownerModuleUUID = stripQuotes(tostring(args[i + 1] or ""))
            i = i + 1
        else
            table.insert(options.unknownArgs, token)
        end

        i = i + 1
    end

    return Options.Normalize(options)
end

---@param options table
---@param testCount integer
---@return boolean
function Options.ShouldUseQuietMode(options, testCount)
    if options.noQuiet == true then
        return false
    end
    if options.quiet == true then
        return true
    end
    return testCount > QUIET_THRESHOLD
end

return Options
