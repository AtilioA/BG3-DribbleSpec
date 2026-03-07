local ConsoleIO = {}

local HELP_TOPICS = {
    "name",
    "tag",
    "context",
    "fail-fast",
    "verbose",
    "mod-uuid",
}

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
    ["verbose"] = "verbose",
    ["--verbose"] = "verbose",
    ["-v"] = "verbose",
    ["mod-uuid"] = "mod-uuid",
    ["--mod-uuid"] = "mod-uuid",
    ["moduuid"] = "mod-uuid",
}

---@param topic string|nil
---@return string|nil
function ConsoleIO.NormalizeHelpTopic(topic)
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

---@param printLine fun(message: string)
local function printOverview(printLine)
    printLine("DribbleSpec CLI")
    printLine("")
    printLine("Usage:")
    printLine("  dribbles [options]")
    printLine("  d [options]")
    printLine("  dribbles --help [topic]")
    printLine("")
    printLine("Options:")
    printLine("  -h, --help [topic]             Show overview help or detailed topic help")
    printLine("  --name <pattern>               Match test fullName by plain case-insensitive substring")
    printLine("  --tag <tag>                    Require tagged tests; repeat to require all tags (AND)")
    printLine("  --context <client|server|any>  Filter by context tag semantics (default: any)")
    printLine("  --fail-fast                    Stop run after first failure")
    printLine("  -v, --verbose                  Print assertion and hook details")
    printLine("  --mod-uuid <uuid>              Caller module UUID for run metadata")
    printLine("")
    printLine("Defaults:")
    printLine("  --context any")
    printLine("")
    printLine("Topic help:")
    printLine("  dribbles --help tag")
    printLine("  dribbles --help context")
    printLine("  dribbles --help --name")
    printLine("")
    printLine("Examples:")
    printLine("  dribbles")
    printLine("  d --name phase2")
    printLine("  dribbles --name phase2")
    printLine("  dribbles --tag runtime --tag server")
    printLine("  dribbles --context server")
end

---@param printLine fun(message: string)
---@param topic string
local function printTopicHelp(printLine, topic)
    if topic == "name" then
        printLine("Topic: name")
        printLine("  Syntax: --name <pattern>")
        printLine("  Matches test fullName by case-insensitive plain substring.")
        printLine("  Example: dribbles --name vendor")
        return true
    end

    if topic == "tag" then
        printLine("Topic: tag")
        printLine("  Syntax: --tag <tag>")
        printLine("  repeatable: each --tag adds another required tag (AND semantics).")
        printLine("  Matching is case-insensitive across suite and test tags.")
        printLine("  Example: dribbles --tag runtime --tag server")
        return true
    end

    if topic == "context" then
        printLine("Topic: context")
        printLine("  Syntax: --context <client|server|any>")
        printLine("  any: include all tests regardless of context tags.")
        printLine("  client: include untagged + client-tagged; exclude server-only tagged tests.")
        printLine("  server: include untagged + server-tagged; exclude client-only tagged tests.")
        printLine("  Client sessions requesting --context server route execution to server context.")
        printLine("  Example: dribbles --context server")
        return true
    end

    if topic == "fail-fast" then
        printLine("Topic: fail-fast")
        printLine("  Syntax: --fail-fast")
        printLine("  Stops execution after the first failure in the current run.")
        printLine("  Example: dribbles --fail-fast")
        return true
    end

    if topic == "verbose" then
        printLine("Topic: verbose")
        printLine("  Syntax: -v | --verbose")
        printLine("  Prints assertion and hook details for each executed test.")
        printLine("  Example: dribbles --verbose")
        return true
    end

    if topic == "mod-uuid" then
        printLine("Topic: mod-uuid")
        printLine("  Syntax: --mod-uuid <uuid>")
        printLine("  Associates the run with a caller module UUID for metadata and diagnostics.")
        printLine("  Example: dribbles --mod-uuid 00000000-0000-0000-0000-000000000000")
        return true
    end

    return false
end

---@param message string
function ConsoleIO.PrintLine(message)
    Ext.Utils.Print(message)
end

---@param message string
function ConsoleIO.PrintWarning(message)
    Ext.Utils.PrintWarning(message)
end

---@param printLine fun(message: string)
---@param topic string|nil
function ConsoleIO.PrintHelp(printLine, topic)
    local resolvedTopic = ConsoleIO.NormalizeHelpTopic(topic)
    if resolvedTopic ~= nil and resolvedTopic ~= "help" then
        local found = printTopicHelp(printLine, resolvedTopic)
        if not found then
            printLine(string.format("Unknown help topic '%s'.", tostring(topic)))
            printLine("Available topics: " .. table.concat(HELP_TOPICS, ", "))
        end
        return
    end

    printOverview(printLine)
end

return ConsoleIO
