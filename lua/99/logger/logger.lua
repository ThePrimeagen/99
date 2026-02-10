local levels = require("99.logger.level")
local time = require("99.time")
local MAX_REQUEST_DEFAULT = 5

--- @type table<number, _99.Logger.RequestLogs>
local logger_cache = {}
local logger_list = {}
local max_requests_in_logger_cache = MAX_REQUEST_DEFAULT

--- @class _99.Logger.Options
--- @field level number?
--- @field type? "print" | "void" | "file"
--- @field path string?
--- @field print_on_error? boolean
--- @field max_requests_cached? number

--- @param ... any
--- @return table<string, any>
local function to_args(...)
  local count = select("#", ...)
  local out = {}
  assert(
    count % 2 == 0,
    "you cannot call logging with an odd number of args. e.g: msg, [k, v]..."
  )
  for i = 1, count, 2 do
    local key = select(i, ...)
    local value = select(i + 1, ...)
    assert(type(key) == "string", "keys in logging must be strings")
    assert(out[key] == nil, "key collision in logs: " .. key)
    out[key] = value
  end
  return out
end

--- @param log_statement table<string, any>
--- @param args table<string, any>
local function put_args(log_statement, args)
  for k, v in pairs(args) do
    assert(log_statement[k] == nil, "key collision in logs: " .. k)
    log_statement[k] = v
  end
end

--- @class LoggerSink
--- @field write_line fun(LoggerSink, string): nil

--- @class VoidLogger : LoggerSink
local VoidSink = {}
VoidSink.__index = VoidSink

function VoidSink.new()
  return setmetatable({}, VoidSink)
end

--- @param _ string
function VoidSink:write_line(_)
  _ = self
end

--- @class FileSink : LoggerSink
--- @field fd number
local FileSink = {}
FileSink.__index = FileSink

--- @param path string
--- @return LoggerSink
function FileSink:new(path)
  -- Ensure the directory is already there (*thanks Windows*)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  -- 420 decimal == 644 octal (rw-r--r--)
  local fd, err = vim.uv.fs_open(path, "w", 420)
  if not fd then
    error("unable to file sink: " .. err)
  end

  return setmetatable({
    fd = fd,
  }, self)
end

--- @param str string
function FileSink:write_line(str)
  local success, err = vim.uv.fs_write(self.fd, str .. "\n")
  if not success then
    error("unable to write to file sink", err)
  end
  vim.uv.fs_fsync(self.fd)
end

--- @class PrintSink : LoggerSink
local PrintSink = {}
PrintSink.__index = PrintSink

--- @return LoggerSink
function PrintSink:new()
  return setmetatable({}, self)
end

--- @param str string
function PrintSink:write_line(str)
  local _ = self
  print(str)
end

--- @class _99.Logger.RequestLogs
--- @field last_access number
--- @field logs string[]

--- @class _99.Logger
--- @field level number
--- @field sink LoggerSink
--- @field print_on_error boolean
--- @field extra_params table<string, any>
local Logger = {}
Logger.__index = Logger

--- @param level number?
--- @return _99.Logger
function Logger:new(level)
  level = level or levels.FATAL
  return setmetatable({
    sink = VoidSink:new(),
    level = level,
    print_on_error = false,
    extra_params = {},
  }, self)
end

--- @return _99.Logger
function Logger:clone()
  local params = {}
  for k, v in pairs(self.extra_params) do
    params[k] = v
  end
  return setmetatable({
    sink = self.sink,
    level = self.level,
    print_on_error = self.print_on_error,
    extra_params = params,
  }, Logger)
end

--- @param path string
--- @return _99.Logger
function Logger:file_sink(path)
  self.sink = FileSink:new(path)
  return self
end

--- @return _99.Logger
function Logger:void_sink()
  self.sink = VoidSink:new()
  return self
end

--- @return _99.Logger
function Logger:print_sink()
  self.sink = PrintSink:new()
  return self
end

--- @param area string
--- @return _99.Logger
function Logger:set_area(area)
  local new_logger = self:clone()
  new_logger.extra_params["Area"] = area
  return new_logger
end

--- @param xid number
--- @return _99.Logger
function Logger:set_id(xid)
  local new_logger = self:clone()
  new_logger.extra_params["id"] = xid
  return new_logger
end

--- @param level number
--- @return _99.Logger
function Logger:set_level(level)
  self.level = level
  return self
end

--- @return _99.Logger
function Logger:on_error_print_message()
  self.print_on_error = true
  return self
end

--- @param opts _99.Logger.Options?
function Logger:configure(opts)
  if not opts then
    return
  end

  if opts.level then
    self:set_level(opts.level)
  end

  if opts.type == "print" then
    self:print_sink()
  elseif opts.type == "file" then
    assert(
      opts.path,
      "if you choose file for logger, you must have a path specified"
    )
    self:file_sink(opts.path)
  else
    self:void_sink()
  end

  if opts.print_on_error then
    self:on_error_print_message()
  end

  max_requests_in_logger_cache = opts.max_requests_cached or MAX_REQUEST_DEFAULT
end

--- @param line string
function Logger:_cache_log(line)
  local id = self.extra_params.id
  if not id then
    return
  end

  local cache = logger_cache[id]
  local new_cache = false
  if not cache then
    cache = {
      last_access = time.now(),
      logs = {},
    }
    logger_cache[id] = cache
    table.insert(logger_list, id)
    new_cache = true
  end
  cache.last_access = time.now()
  table.insert(cache.logs, line)
  table.sort(logger_list, function(a, b)
    assert(
      logger_cache[a] and logger_cache[b],
      "logger list is out of sync with logger cache: "
        .. tostring(a)
        .. " and "
        .. tostring(b)
    )
    local a_time = logger_cache[a].last_access
    local b_time = logger_cache[b].last_access
    return a_time > b_time
  end)

  if not new_cache then
    return
  end

  Logger._trim_cache()
end

--- This is a _TEST ONLY_ function.  you should not call this function outside
--- of unit tests
function Logger.reset()
  logger_cache = {}
  max_requests_in_logger_cache = MAX_REQUEST_DEFAULT
end

--- @return string[][]
function Logger.logs()
  local out = {}
  for _, id in ipairs(logger_list) do
    local request_logs = logger_cache[id]
    table.insert(out, request_logs.logs)
  end
  return out
end

--- @param level number
---@param msg string
---@param ... any
function Logger:_log(level, msg, ...)
  if self.level > level then
    return
  end

  local log_statement = {
    level = levels.levelToString(level),
    msg = msg,
  }

  put_args(log_statement, to_args(...))
  put_args(log_statement, self.extra_params)

  assert(log_statement["id"], "every log must have an id associated with it")

  local json_string = vim.json.encode(log_statement)
  if self.print_on_error and level == levels.ERROR then
    print(json_string)
  end

  self:_cache_log(json_string)
  self.sink:write_line(json_string)
end

--- @param msg string
--- @param ... any
function Logger:info(msg, ...)
  self:_log(levels.INFO, msg, ...)
end

--- @param msg string
--- @param ... any
function Logger:warn(msg, ...)
  self:_log(levels.WARN, msg, ...)
end

--- @param msg string
--- @param ... any
function Logger:debug(msg, ...)
  self:_log(levels.DEBUG, msg, ...)
end

--- @param msg string
--- @param ... any
function Logger:error(msg, ...)
  self:_log(levels.ERROR, msg, ...)
end

--- @param msg string
--- @param ... any
function Logger:fatal(msg, ...)
  self:_log(levels.FATAL, msg, ...)
  assert(false, "fatal msg recieved: " .. msg, ...)
end

--- @param test any
---@param msg string
---@param ... any
function Logger:assert(test, msg, ...)
  if not test then
    self:fatal(msg, ...)
  end
end

function Logger._trim_cache()
  local count = 0
  local oldest = nil
  local oldest_key = nil
  for k, log in pairs(logger_cache) do
    if oldest == nil or log.last_access < oldest.last_access then
      oldest = log
      oldest_key = k
    end
    count = count + 1
  end

  if count > max_requests_in_logger_cache then
    assert(oldest_key, "oldest key must exist")
    logger_cache[oldest_key] = nil

    for i, id in ipairs(logger_list) do
      if id == oldest_key then
        table.remove(logger_list, i)
        break
      end
    end
  end
end

function Logger.set_max_cached_requests(count)
  max_requests_in_logger_cache = count
  Logger._trim_cache()
end

local module_logger = Logger:new(levels.DEBUG)

return module_logger
