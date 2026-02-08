local Logger = require("99.logger.logger")
local Level = require("99.logger.level")
local ops = require("99.ops")
local Languages = require("99.language")
local Window = require("99.window")
local get_id = require("99.id")
local RequestContext = require("99.request-context")
local geo = require("99.geo")
local Range = geo.Range
local Point = geo.Point
local Extensions = require("99.extensions")
local Agents = require("99.extensions.agents")
local Providers = require("99.providers")
local time = require("99.time")

---@param path_or_rule string | _99.Agents.Rule
---@return _99.Agents.Rule | string
local function expand(path_or_rule)
  if type(path_or_rule) == "string" then
    return vim.fn.expand(path_or_rule)
  end
  return {
    name = path_or_rule.name,
    path = vim.fn.expand(path_or_rule.path),
  }
end

--- @param opts _99.ops.Opts?
--- @return _99.ops.Opts
local function process_opts(opts)
  opts = opts or {}
  for i, rule in ipairs(opts.additional_rules or {}) do
    local r = expand(rule)
    assert(
      type(r) ~= "string",
      "broken configuration.  additional_rules must never be a string"
    )
    opts.additional_rules[i] = r
  end
  return opts
end

--- @alias _99.Cleanup fun(): nil

--- @class _99.RequestEntry
--- @field id number
--- @field operation string
--- @field status "running" | "success" | "failed" | "cancelled"
--- @field filename string
--- @field lnum number
--- @field col number
--- @field started_at number

--- @class _99.ActiveRequest
--- @field clean_up _99.Cleanup
--- @field request_id number

--- @class _99.StateProps
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field languages string[]
--- @field display_errors boolean
--- @field auto_add_skills boolean
--- @field provider_override _99.Providers.BaseProvider?
--- @field __active_requests table<number, _99.ActiveRequest>
--- @field __view_log_idx number
--- @field __request_history _99.RequestEntry[]
--- @field __request_by_id table<number, _99.RequestEntry>

--- @return _99.StateProps
local function create_99_state()
  return {
    model = "opencode/claude-sonnet-4-5",
    md_files = {},
    prompts = require("99.prompt-settings"),
    ai_stdout_rows = 3,
    languages = { "lua", "go", "java", "elixir", "cpp", "ruby" },
    display_errors = false,
    provider_override = nil,
    auto_add_skills = false,
    __active_requests = {},
    __view_log_idx = 1,
    __request_history = {},
    __request_by_id = {},
  }
end

--- @class _99.Completion
--- @field source "cmp" | nil
--- @field custom_rules string[]

--- @class _99.Options
--- @field logger _99.Logger.Options?
--- @field model string?
--- @field md_files string[]?
--- @field provider _99.Providers.BaseProvider?
--- @field debug_log_prefix string?
--- @field display_errors? boolean
--- @field auto_add_skills? boolean
--- @field completion _99.Completion?

--- unanswered question -- will i need to queue messages one at a time or
--- just send them all...  So to prepare ill be sending around this state object
--- @class _99.State
--- @field completion _99.Completion
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field languages string[]
--- @field display_errors boolean
--- @field provider_override _99.Providers.BaseProvider?
--- @field auto_add_skills boolean
--- @field rules _99.Agents.Rules
--- @field __active_requests table<number, _99.ActiveRequest>
--- @field __view_log_idx number
--- @field __request_history _99.RequestEntry[]
--- @field __request_by_id table<number, _99.RequestEntry>
local _99_State = {}
_99_State.__index = _99_State

--- @return _99.State
function _99_State.new()
  local props = create_99_state()
  ---@diagnostic disable-next-line: return-type-mismatch
  return setmetatable(props, _99_State)
end

--- TODO: This is something to understand.  I bet that this is going to need
--- a lot of performance tuning.  I am just reading every file, and this could
--- take a decent amount of time if there are lots of rules.
---
--- Simple perfs:
--- 1. read 4096 bytes at a tiem instead of whole file and parse out lines
--- 2. don't show the docs
--- 3. do the operation once at setup instead of every time.
---    likely not needed to do this all the time.
function _99_State:refresh_rules()
  self.rules = Agents.rules(self)
  Extensions.refresh(self)
end

--- @param context _99.RequestContext
--- @return _99.RequestEntry
function _99_State:track_request(context)
  local point = context.range and context.range.start or Point:from_cursor()
  local entry = {
    id = context.xid,
    operation = context.operation or "request",
    status = "running",
    filename = context.full_path,
    lnum = point.row,
    col = point.col,
    started_at = time.now(),
  }
  table.insert(self.__request_history, entry)
  self.__request_by_id[entry.id] = entry
  return entry
end

--- @param id number
--- @param status "success" | "failed" | "cancelled"
function _99_State:finish_request(id, status)
  local entry = self.__request_by_id[id]
  if entry then
    entry.status = status
  end
end

--- @param id number
function _99_State:remove_request(id)
  for i, entry in ipairs(self.__request_history) do
    if entry.id == id then
      table.remove(self.__request_history, i)
      break
    end
  end
  self.__request_by_id[id] = nil
end

--- @return number
function _99_State:previous_request_count()
  local count = 0
  for _, entry in ipairs(self.__request_history) do
    if entry.status ~= "running" then
      count = count + 1
    end
  end
  return count
end

function _99_State:clear_previous_requests()
  local keep = {}
  for _, entry in ipairs(self.__request_history) do
    if entry.status == "running" then
      table.insert(keep, entry)
    else
      self.__request_by_id[entry.id] = nil
    end
  end
  self.__request_history = keep
end

local _active_request_id = 0
---@param clean_up _99.Cleanup
---@param request_id number
---@return number
function _99_State:add_active_request(clean_up, request_id)
  _active_request_id = _active_request_id + 1
  Logger:debug("adding active request", "id", _active_request_id)
  self.__active_requests[_active_request_id] = {
    clean_up = clean_up,
    request_id = request_id,
  }
  return _active_request_id
end

function _99_State:active_request_count()
  local count = 0
  for _ in pairs(self.__active_requests) do
    count = count + 1
  end
  return count
end

---@param id number
function _99_State:remove_active_request(id)
  local logger = Logger:set_id(id)
  local r = self.__active_requests[id]
  logger:assert(r, "there is no active request for id.  implementation broken")
  logger:debug("removing active request")
  self.__active_requests[id] = nil
end

local _99_state = _99_State.new()

--- @class _99
local _99 = {
  DEBUG = Level.DEBUG,
  INFO = Level.INFO,
  WARN = Level.WARN,
  ERROR = Level.ERROR,
  FATAL = Level.FATAL,
}

--- you can only set those marks after the visual selection is removed
local function set_selection_marks()
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
    "x",
    false
  )
end

--- @param cb fun(ok: boolean, o: _99.ops.Opts?): nil
--- @param context _99.RequestContext
--- @param opts _99.ops.Opts
--- @return fun(ok: boolean, response: string): nil
local function wrap_window_capture(cb, context, opts)
  --- @param ok boolean
  --- @param response string
  return function(ok, response)
    context.logger:debug("capture_prompt", "success", ok, "response", response)
    if not ok then
      return cb(false)
    end
    local rules_and_names = Agents.by_name(_99_state.rules, response)
    opts.additional_rules = opts.additional_rules or {}
    for _, r in ipairs(rules_and_names.rules) do
      table.insert(opts.additional_rules, r)
    end
    opts.additional_prompt = response
    cb(true, opts)
  end
end

--- @param operation_name string
--- @return _99.RequestContext
local function get_context(operation_name)
  _99_state:refresh_rules()
  local trace_id = get_id()
  local context = RequestContext.from_current_buffer(_99_state, trace_id)
  context.operation = operation_name
  context.logger:debug("99 Request", "method", operation_name)
  return context
end

function _99.info()
  local info = {}
  _99_state:refresh_rules()
  table.insert(
    info,
    string.format("Previous Requests: %d", _99_state:previous_request_count())
  )
  table.insert(
    info,
    string.format("custom rules(%d):", #(_99_state.rules.custom or {}))
  )
  for _, rule in ipairs(_99_state.rules.custom or {}) do
    table.insert(info, string.format("* %s", rule.name))
  end
  Window.display_centered_message(info)
end

--- @param path string
function _99:rule_from_path(path)
  _ = self
  path = expand(path) --[[ @as string]]
  return Agents.get_rule_by_path(_99_state.rules, path)
end

--- @param opts? _99.ops.Opts
function _99.fill_in_function_prompt(opts)
  opts = process_opts(opts)
  local context = get_context("fill-in-function-with-prompt")

  context.logger:debug("start")
  Window.capture_input({
    cb = wrap_window_capture(function(ok, o)
      if not ok then
        return
      end
      assert(o ~= nil, "if ok, then opts must exist")
      ops.fill_in_function(context, o)
    end, context, opts),
    on_load = function()
      Extensions.setup_buffer(_99_state)
    end,
    rules = _99_state.rules,
  })
end

--- @param opts? _99.ops.Opts
function _99.fill_in_function(opts)
  opts = process_opts(opts)
  ops.fill_in_function(get_context("fill_in_function"), opts)
end

--- @param opts _99.ops.Opts
function _99.visual_prompt(opts)
  opts = process_opts(opts)
  local context = get_context("over-range-with-prompt")
  context.logger:debug("start")
  Window.capture_input({
    cb = wrap_window_capture(function(ok, o)
      if not ok then
        return
      end
      assert(o ~= nil, "if ok, then opts must exist")
      _99.visual(context, o)
    end, context, opts),
    on_load = function()
      Extensions.setup_buffer(_99_state)
    end,
    rules = _99_state.rules,
  })
end

--- @param context _99.RequestContext?
--- @param opts _99.ops.Opts?
function _99.visual(context, opts)
  opts = process_opts(opts)
  --- TODO: Talk to teej about this.
  --- Visual selection marks are only set in place post visual selection.
  --- that means for this function to work i must escape out of visual mode
  --- which i dislike very much.  because maybe you dont want this
  set_selection_marks()

  context = context or get_context("over-range")
  local range = Range.from_visual_selection()
  ops.over_range(context, range, opts)
end

--- View all the logs that are currently cached.  Cached log count is determined
--- by _99.Logger.Options that are passed in.
function _99.view_logs()
  _99_state.__view_log_idx = 1
  local logs = Logger.logs()
  if #logs == 0 then
    print("no logs to display")
    return
  end
  Window.display_full_screen_message(logs[1])
end

function _99.prev_request_logs()
  local logs = Logger.logs()
  if #logs == 0 then
    print("no logs to display")
    return
  end
  _99_state.__view_log_idx = math.min(_99_state.__view_log_idx + 1, #logs)
  Window.display_full_screen_message(logs[_99_state.__view_log_idx])
end

function _99.next_request_logs()
  local logs = Logger.logs()
  if #logs == 0 then
    print("no logs to display")
    return
  end
  _99_state.__view_log_idx = math.max(_99_state.__view_log_idx - 1, 1)
  Window.display_full_screen_message(logs[_99_state.__view_log_idx])
end

function _99.stop_all_requests()
  for _, active in pairs(_99_state.__active_requests) do
    _99_state:remove_request(active.request_id)
    active.clean_up()
  end
  _99_state.__active_requests = {}
end

function _99.previous_requests_to_qfix()
  local items = {}
  for _, entry in ipairs(_99_state.__request_history) do
    table.insert(items, {
      filename = entry.filename,
      lnum = entry.lnum,
      col = entry.col,
      text = string.format("[%s] %s", entry.status, entry.operation),
    })
  end
  vim.fn.setqflist({}, "r", { title = "99 Requests", items = items })
  vim.cmd("copen")
end

function _99.clear_previous_requests()
  _99_state:clear_previous_requests()
end

--- if you touch this function you will be fired
--- @return _99.State
function _99.__get_state()
  return _99_state
end

--- @param opts _99.Options?
function _99.setup(opts)
  opts = opts or {}
  _99_state = _99_State.new()
  _99_state.provider_override = opts.provider
  _99_state.completion = opts.completion
    or {
      source = nil,
      custom_rules = {},
    }
  _99_state.completion.custom_rules = _99_state.completion.custom_rules or {}
  _99_state.auto_add_skills = opts.auto_add_skills or false

  local crules = _99_state.completion.custom_rules
  for i, rule in ipairs(crules) do
    local str = expand(rule)
    assert(type(str) == "string", "rule path must be a string")
    crules[i] = str
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      _99.stop_all_requests()
    end,
  })

  Logger:configure(opts.logger)

  if opts.model then
    assert(type(opts.model) == "string", "opts.model is not a string")
    _99_state.model = opts.model
  else
    local provider = opts.provider or Providers.OpenCodeProvider
    if provider._get_default_model then
      _99_state.model = provider._get_default_model()
    end
  end

  if opts.md_files then
    assert(type(opts.md_files) == "table", "opts.md_files is not a table")
    for _, md in ipairs(opts.md_files) do
      _99.add_md_file(md)
    end
  end

  _99_state.display_errors = opts.display_errors or false
  _99_state:refresh_rules()
  Languages.initialize(_99_state)
  Extensions.init(_99_state)
end

--- @param md string
--- @return _99
function _99.add_md_file(md)
  table.insert(_99_state.md_files, md)
  return _99
end

--- @param md string
--- @return _99
function _99.rm_md_file(md)
  for i, name in ipairs(_99_state.md_files) do
    if name == md then
      table.remove(_99_state.md_files, i)
      break
    end
  end
  return _99
end

--- @param model string
--- @return _99
function _99.set_model(model)
  _99_state.model = model
  return _99
end

function _99.__debug()
  Logger:configure({
    path = nil,
    level = Level.DEBUG,
  })
end

_99.Providers = Providers

return _99
