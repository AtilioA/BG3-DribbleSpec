local Filter = {}

---@param metadata table|nil
---@param tagSet table<string, boolean>
local function addMetadataTags(metadata, tagSet)
    if type(metadata) ~= "table" or type(metadata.tags) ~= "table" then
        return
    end

    for _, tag in ipairs(metadata.tags) do
        if type(tag) == "string" and tag ~= "" then
            tagSet[string.lower(tag)] = true
        end
    end
end

---@param lineage table[]|nil
---@param test table|nil
---@return table<string, boolean>
local function collectTagSet(lineage, test)
    local tagSet = {}

    for _, suite in ipairs(lineage or {}) do
        addMetadataTags(suite.metadata, tagSet)
    end

    if test then
        addMetadataTags(test.metadata, tagSet)
    end

    return tagSet
end

---@param pattern string
---@param fullName string
---@return boolean
local function matchesNamePattern(pattern, fullName)
    if pattern == "" then
        return true
    end

    local candidate = string.lower(tostring(fullName or ""))
    return string.find(candidate, pattern, 1, true) ~= nil
end

---@param requiredTags string[]
---@param tagSet table<string, boolean>
---@return boolean
local function matchesRequiredTags(requiredTags, tagSet)
    for _, requiredTag in ipairs(requiredTags) do
        if tagSet[requiredTag] ~= true then
            return false
        end
    end

    return true
end

---@param context string
---@param tagSet table<string, boolean>
---@return boolean
local function matchesContext(context, tagSet)
    if context ~= "client" and context ~= "server" then
        return true
    end

    if tagSet[context] == true then
        return true
    end

    local opposite = context == "client" and "server" or "client"
    if tagSet[opposite] == true then
        return false
    end

    return true
end

---@param options table|nil
---@return table
function Filter.Create(options)
    local normalized = options or {}
    local requiredTags = {}
    for _, tag in ipairs(normalized.tags or {}) do
        if type(tag) == "string" and tag ~= "" then
            table.insert(requiredTags, string.lower(tag))
        end
    end

    local namePattern = ""
    if type(normalized.namePattern) == "string" then
        namePattern = string.lower(normalized.namePattern)
    end

    local context = "any"
    if type(normalized.context) == "string" then
        context = string.lower(normalized.context)
    end

    local filter = {}

    ---@param lineage table[]|nil
    ---@param test table
    ---@return boolean
    function filter.ShouldIncludeTest(lineage, test)
        if not matchesNamePattern(namePattern, test and test.fullName or "") then
            return false
        end

        local tagSet = collectTagSet(lineage, test)
        if not matchesRequiredTags(requiredTags, tagSet) then
            return false
        end

        if not matchesContext(context, tagSet) then
            return false
        end

        return true
    end

    return filter
end

return Filter
