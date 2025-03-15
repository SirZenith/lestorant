local M = {}

---@enum log.LogLevel
local LogLevel = {
    trace = 1,
    debug = 2,
    info = 3,
    warn = 4,
    error = 5,
    silent = 6,
}
M.LogLevel = LogLevel

---@type table<log.LogLevel, string>
local LEVEL_TEXT = {
    [LogLevel.trace] = "[TRACE] ",
    [LogLevel.debug] = "[DEBUG] ",
    [LogLevel.info]  = "[ INFO] ",
    [LogLevel.warn]  = "[ WARN] ",
    [LogLevel.error] = "[ERROR] ",
}

---@class log.Logger
---@field name string
---@field file file*
---@field level log.LogLevel
local Logger = {}
M.Logger = Logger

Logger.name = "logger"
Logger.file = io.stderr
Logger.level = LogLevel.trace

-- set_global_log_level sets a minum log level. Any log that has level lower than
-- this will not get printed.
---@param level log.LogLevel
function M.set_global_log_level(level)
    Logger.level = level
end

---@param name string
---@return log.Logger
function Logger:new(name)
    self.__index = self

    local obj = setmetatable({}, self);
    obj.name = name

    return obj
end

-- set_level sets log level of current logger.
---@param level log.LogLevel
function Logger:set_level(level)
    self.level = level
end

-- log prints log message with given log level. If current logger level is higher
-- than given level, no message will be printed.
---@param level log.LogLevel
---@param ... any
function Logger:log(level, ...)
    if self.level > level or Logger.level > level then
        return
    end

    local file = self.file
    file:write(LEVEL_TEXT[level] or "")
    file:write("[", self.name, "] ")

    for _, value in ipairs { ... } do
        file:write(tostring(value))
    end
end

-- logln works like `log`, but adding new line at the end of log message.
---@param level log.LogLevel
---@param ... any
function Logger:logln(level, ...)
    if self.level > level or Logger.level > level then
        return
    end
    self:log(level, ...)
    self.file:write("\n")
end

-- trace prints message in trace level.
function Logger:trace(...)
    self:log(LogLevel.trace, ...)
end

-- trace prints message in trace level with new line.
function Logger:traceln(...)
    self:logln(LogLevel.trace, ...)
end

-- debug prints message in debug level.
function Logger:debug(...)
    self:log(LogLevel.debug, ...)
end

-- debug prints message in debug level with new line.
function Logger:debugln(...)
    self:logln(LogLevel.debug, ...)
end

-- info prints message in info level.
function Logger:info(...)
    self:log(LogLevel.info, ...)
end

-- info prints message in info level with new line.
function Logger:infoln(...)
    self:logln(LogLevel.info, ...)
end

-- warn prints message in warn level.
function Logger:warn(...)
    self:log(LogLevel.warn, ...)
end

-- warn prints message in warn level with new line
function Logger:warnln(...)
    self:logln(LogLevel.warn, ...)
end

-- error prints message in error level.
function Logger:error(...)
    self:log(LogLevel.error, ...)
end

-- error prints message in error level with new line.
function Logger:errorln(...)
    self:logln(LogLevel.error, ...)
end

return M
