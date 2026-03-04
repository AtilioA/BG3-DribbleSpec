local ConsoleIO = {}

local HELP_TOPICS = {
    "name",
    "tag",
    "context",
    "fail-fast",
    "mod-uuid",
    "json-out",
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
    ["mod-uuid"] = "mod-uuid",
    ["--mod-uuid"] = "mod-uuid",
    ["moduuid"] = "mod-uuid",
    ["json-out"] = "json-out",
    ["--json-out"] = "json-out",
    ["jsonout"] = "json-out",
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
    printLine("  dribble [options]")
    printLine("  dribble --help [topic]")
    printLine("")
    printLine("Options:")
    printLine("  -h, --help [topic]             Show overview help or detailed topic help")
    printLine("  --name <pattern>               Match test fullName by plain case-insensitive substring")
    printLine("  --tag <tag>                    Require tagged tests; repeat to require all tags (AND)")
    printLine("  --context <client|server|any>  Filter by context tag semantics (default: any)")
    printLine("  --fail-fast                    Stop run after first failure")
    printLine("  --mod-uuid <uuid>              Caller module UUID for run metadata")
    printLine("  --json-out <path>              Reserved output path for JSON report metadata")
    printLine("")
    printLine("Defaults:")
    printLine("  --context any")
    printLine("")
    printLine("Topic help:")
    printLine("  dribble --help tag")
    printLine("  dribble --help context")
    printLine("  dribble --help --name")
    printLine("")
    printLine("Examples:")
    printLine("  dribble")
    printLine("  dribble --name phase2")
    printLine("  dribble --tag runtime --tag server")
    printLine("  dribble --context server")
end

---@param printLine fun(message: string)
---@param topic string
local function printTopicHelp(printLine, topic)
    if topic == "name" then
        printLine("Topic: name")
        printLine("  Syntax: --name <pattern>")
        printLine("  Matches test fullName by case-insensitive plain substring.")
        printLine("  Example: dribble --name vendor")
        return true
    end

    if topic == "tag" then
        printLine("Topic: tag")
        printLine("  Syntax: --tag <tag>")
        printLine("  repeatable: each --tag adds another required tag (AND semantics).")
        printLine("  Matching is case-insensitive across suite and test tags.")
        printLine("  Example: dribble --tag runtime --tag server")
        return true
    end

    if topic == "context" then
        printLine("Topic: context")
        printLine("  Syntax: --context <client|server|any>")
        printLine("  any: include all tests regardless of context tags.")
        printLine("  client: include untagged + client-tagged; exclude server-only tagged tests.")
        printLine("  server: include untagged + server-tagged; exclude client-only tagged tests.")
        printLine("  Client sessions requesting --context server route execution to server context.")
        printLine("  Example: dribble --context server")
        return true
    end

    if topic == "fail-fast" then
        printLine("Topic: fail-fast")
        printLine("  Syntax: --fail-fast")
        printLine("  Stops execution after the first failure in the current run.")
        printLine("  Example: dribble --fail-fast")
        return true
    end

    if topic == "mod-uuid" then
        printLine("Topic: mod-uuid")
        printLine("  Syntax: --mod-uuid <uuid>")
        printLine("  Associates the run with a caller module UUID for metadata and diagnostics.")
        printLine("  Example: dribble --mod-uuid 00000000-0000-0000-0000-000000000000")
        return true
    end

    if topic == "json-out" then
        printLine("Topic: json-out")
        printLine("  Syntax: --json-out <path>")
        printLine("  Sets preferred JSON output path metadata for report workflows.")
        printLine("  Example: dribble --json-out DribbleSpec/results.json")
        return true
    end

    return false
end

---@param message string
function ConsoleIO.PrintLine(message)
    if type(Ext) == "table" and type(Ext.Utils) == "table" and type(Ext.Utils.Print) == "function" then
        Ext.Utils.Print(message)
        return
    end

    if type(print) == "function" then
        print(message)
    end
end

---@param message string
function ConsoleIO.PrintWarning(message)
    if type(Ext) == "table" and type(Ext.Utils) == "table" and type(Ext.Utils.PrintWarning) == "function" then
        Ext.Utils.PrintWarning(message)
        return
    end

    ConsoleIO.PrintLine(message)
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
