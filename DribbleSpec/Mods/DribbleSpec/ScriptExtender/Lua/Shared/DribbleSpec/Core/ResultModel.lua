local ResultModel = {}

---@param context string
---@param options table
---@param startedAtMs integer
---@return table
function ResultModel.NewRun(context, options, startedAtMs)
    return {
        framework = "DribbleSpec",
        version = "0.1.0-phase0",
        status = "passed",
        context = context or "unknown",
        options = options or {},
        summary = {
            passed = 0,
            failed = 0,
            skipped = 0,
            total = 0,
        },
        suites = {},
        warnings = {},
        startedAtMs = startedAtMs or 0,
        finishedAtMs = startedAtMs or 0,
        durationMs = 0,
    }
end

---@param run table
---@param message string
function ResultModel.AddWarning(run, message)
    table.insert(run.warnings, message)
end

---@param run table
---@param finishedAtMs integer
---@return table
function ResultModel.Finalize(run, finishedAtMs)
    run.finishedAtMs = finishedAtMs or run.startedAtMs
    run.durationMs = math.max(0, run.finishedAtMs - run.startedAtMs)
    run.summary.total = (run.summary.passed or 0) + (run.summary.failed or 0) + (run.summary.skipped or 0)
    run.status = ((run.summary.failed or 0) > 0) and "failed" or "passed"
    return run
end

return ResultModel
