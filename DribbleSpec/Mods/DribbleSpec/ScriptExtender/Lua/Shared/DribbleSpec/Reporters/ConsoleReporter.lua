local ConsoleReporter = {}

local RESET = "\x1b[0m"
local BOLD = "\x1b[1m"

local COLORS = {
    white = "\x1b[38;2;255;255;255m",
    cyan = "\x1b[38;2;58;183;255m",
    green = "\x1b[38;2;21;255;81m",
    red = "\x1b[38;2;255;10;40m",
    yellow = "\x1b[38;2;255;214;10m",
    gray = "\x1b[38;2;145;145;145m",
}

---@param text string
---@param colorCode string
---@param bold boolean|nil
---@return string
local function color(text, colorCode, bold)
    local prefix = colorCode
    if bold then
        prefix = prefix .. BOLD
    end

    return prefix .. tostring(text) .. RESET
end

---@param status string|nil
---@return string
local function statusIcon(status)
    if status == "passed" then
        return color("■", COLORS.green)
    end

    if status == "failed" then
        return color("■", COLORS.red)
    end

    return color("■", COLORS.yellow)
end

---@param suite table
---@return integer, integer, integer
local function countSuiteStatus(suite)
    local passed = 0
    local failed = 0
    local skipped = 0

    for _, test in ipairs(suite.tests or {}) do
        if test.status == "passed" then
            passed = passed + 1
        elseif test.status == "failed" then
            failed = failed + 1
        else
            skipped = skipped + 1
        end
    end

    for _, child in ipairs(suite.suites or {}) do
        local childPassed, childFailed, childSkipped = countSuiteStatus(child)
        passed = passed + childPassed
        failed = failed + childFailed
        skipped = skipped + childSkipped
    end

    return passed, failed, skipped
end

---@param status string
---@param count integer
---@return string
local function statusBar(status, count)
    if count <= 0 then
        return "0"
    end

    return string.rep(statusIcon(status), count)
end

---@param label string
---@param status string|nil
---@param value integer
---@return string
local function summaryMetricLine(label, status, value)
    local countText = string.format("%s (%d):", label, value)
    local metricValue = tostring(value)

    if status then
        metricValue = statusBar(status, value)
    end

    return string.format("  %s %s", color(countText, COLORS.white), metricValue)
end

---@param lines string[]
---@param suite table
---@param depth integer
local function appendSuiteLines(lines, suite, depth)
    local indent = string.rep("  ", depth)
    local passed, failed, skipped = countSuiteStatus(suite)
    local suiteName = tostring(suite.name or "[unnamed suite]")
    local metrics = {}

    if passed > 0 then
        table.insert(metrics, string.format("%s %s", statusIcon("passed"), color(tostring(passed), COLORS.green, true)))
    end

    if failed > 0 then
        table.insert(metrics, string.format("%s %s", statusIcon("failed"), color(tostring(failed), COLORS.red, true)))
    end

    if skipped > 0 then
        table.insert(metrics, string.format("%s %s", statusIcon("skipped"), color(tostring(skipped), COLORS.yellow, true)))
    end

    local metricsText = ""
    if #metrics > 0 then
        metricsText = "  " .. table.concat(metrics, "  ")
    end

    table.insert(lines,
        string.format("%s%s %s%s",
            indent,
            color("Suite:", COLORS.cyan, true),
            color(suiteName, COLORS.white, true),
            metricsText
        ))

    for _, test in ipairs(suite.tests or {}) do
        local icon = statusIcon(test.status)
        table.insert(lines, string.format("%s  %s %s", indent, icon, tostring(test.name or "[unnamed test]")))

        if test.status == "failed" and test.error and test.error.message then
            table.insert(lines, string.format("%s    %s %s", indent, color("failure:", COLORS.red, true),
                color(tostring(test.error.message), COLORS.red)))
        elseif test.status == "skipped" and test.skipReason then
            table.insert(lines, string.format("%s    %s %s", indent, color("skip:", COLORS.yellow, true),
                color(tostring(test.skipReason), COLORS.yellow)))
        end
    end

    for _, childSuite in ipairs(suite.suites or {}) do
        appendSuiteLines(lines, childSuite, depth + 1)
    end
end

---@param runResult table
---@return string[] lines
function ConsoleReporter.BuildLines(runResult)
    local lines = {}
    local summary = runResult.summary or {}
    local failed = summary.failed or 0
    local passed = summary.passed or 0
    local skipped = summary.skipped or 0
    local total = summary.total or 0
    local status = tostring(runResult.status or "unknown")
    local context = tostring(runResult.context or "unknown")
    local durationMs = tonumber(runResult.durationMs or 0) or 0

    local runStatusText = status == "failed" and color("FAILED", COLORS.red, true) or color("PASSED", COLORS.green, true)
    table.insert(lines,
        string.format("%s %s %s  %s %s  %s %s",
            color("[DribbleSpec]", COLORS.cyan, true),
            statusIcon(status),
            color("Run", COLORS.white, true),
            color("status:", COLORS.gray),
            runStatusText,
            color("context:", COLORS.gray),
            color(context, COLORS.white, true)
        ))

    table.insert(lines, color("", COLORS.gray))
    table.insert(lines, color("RESULTS", COLORS.white, true))
    for _, suite in ipairs(runResult.suites or {}) do
        appendSuiteLines(lines, suite, 0)
    end

    table.insert(lines, color("", COLORS.gray))
    table.insert(lines, color("SUMMARY", COLORS.white, true))
    table.insert(lines, summaryMetricLine("Passed", "passed", passed))
    table.insert(lines, summaryMetricLine("Failed", "failed", failed))
    table.insert(lines, summaryMetricLine("Skipped", "skipped", skipped))
    table.insert(lines, summaryMetricLine("Total", nil, total))
    table.insert(lines, summaryMetricLine("DurationMs", nil, durationMs))

    return lines
end

---@param runResult table
---@param sinks table|nil
function ConsoleReporter.PrintRun(runResult, sinks)
    local output = sinks or {}
    local printLine = output.printLine
    local printWarning = output.printWarning

    if type(printLine) ~= "function" then
        printLine = function(message)
            Ext.Utils.Print(message)
        end
    end

    if type(printWarning) ~= "function" then
        printWarning = function(message)
            Ext.Utils.PrintWarning(message)
        end
    end

    for _, line in ipairs(ConsoleReporter.BuildLines(runResult)) do
        printLine(line)
    end

    for _, warning in ipairs(runResult.warnings or {}) do
        printWarning(string.format("%s %s", color("[DribbleSpec warning]", COLORS.yellow, true), tostring(warning)))
    end
end

return ConsoleReporter
