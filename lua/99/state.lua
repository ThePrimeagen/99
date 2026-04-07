local utils = require("99.utils")
local Agents = require("99.extensions.agents")
local Extensions = require("99.extensions")
local Tracking = require("99.state.tracking")
local Window = require("99.window")

local _99_STATE_FILE = "state"
local function default_completion()
  return { source = nil, custom_rules = {} }
end

--- @class _99.StateProps
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field display_errors boolean
--- @field auto_add_skills boolean
--- @field provider_override _99.Providers.BaseProvider | nil
--- @field __view_log_idx number
--- @field __tmp_dir string | nil

--- unanswered question -- will i need to queue messages one at a time or
--- just send them all...  So to prepare ill be sending around this state object
--- @class _99.State
--- @field completion _99.Completion
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field display_errors boolean
--- @field provider_override _99.Providers.BaseProvider?
--- @field provider_extra_args string[]
--- @field rules _99.Agents.Rules
--- @field tracking _99.State.Tracking
--- @field __tmp_dir string | nil
local State = {}
State.__index = State

--- @return _99.StateProps
local function create()
  return {
    model = "opencode/claude-sonnet-4-5",
    md_files = {},
    ai_stdout_rows = 3,
    display_errors = false,
    provider_override = nil,
    tmp_dir = nil,
  }
end

--- @param oos _99.Options | _99.State
local function get_tmp_dir(oos)
  local tmp_dir = oos.tmp_dir and type(oos.tmp_dir) == "string" and oos.tmp_dir
    or oos.__tmp_dir and oos.__tmp_dir
    or "./tmp"
  if tmp_dir then
    tmp_dir = vim.fn.expand(tmp_dir)
  end
  return tmp_dir
end

--- @param opts _99.Options
--- @return _99.State.Tracking.Serialized | nil
local function read_state_from_tmp(opts)
  local state_file = utils.named_tmp_file(get_tmp_dir(opts), _99_STATE_FILE)
  return utils.read_file_json_safe(state_file) --[[@as _99.State.Tracking.Serialized]]
end

--- @param opts _99.Options
--- @return _99.State
function State.new(opts)
  local props = create()
  local _99_state = setmetatable(props, State) --[[@as _99.State]]

  _99_state.provider_override = opts.provider
  _99_state.provider_extra_args = opts.provider_extra_args or {}
  _99_state.completion = opts.completion or default_completion()
  _99_state.completion.custom_rules = _99_state.completion.custom_rules or {}
  _99_state.completion.files = _99_state.completion.files or {}

  --- TODO: Prompt overrides would be a great thing, we just have to get there
  --- for now, i am going to have this as just a hardcoded ... thing
  _99_state.prompts = require("99.prompt-settings")

  local previous = read_state_from_tmp(opts)
  _99_state.tracking = Tracking.new(_99_state, previous)

  return _99_state
end

function State:sync()
  local tracking = self.tracking:serialize()
  local tmp = self:tmp_dir()
  local file = utils.named_tmp_file(tmp, _99_STATE_FILE)
  utils.write_file_json_safe(tracking, file)
end

--- @return string
function State:tmp_dir()
  return get_tmp_dir(self)
end

--- @return boolean
function State:active()
  _ = self
  if Window.has_active_window() then
    return true
  end

  local qf = vim.fn.getqflist({ winid = 0 })
  return qf.winid ~= 0
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
function State:refresh_rules()
  self.rules = Agents.rules(self)
  Extensions.refresh(self)
end

return State
