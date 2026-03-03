local ConsoleIO = {}

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
function ConsoleIO.PrintHelp(printLine)
    printLine("DribbleSpec (Phase 1) usage:")
    printLine("  dribble [--help] [--manifest <path>] [--name <pattern>] [--tag <tag>] [--context <client|server|any>] [--fail-fast] [--mod-uuid <uuid>] [--json-out <path>]")
    printLine("Defaults:")
    printLine("  --manifest DribbleTests.lua")
end

return ConsoleIO
