--- TODO: I would like to clean up this file.  I will probably need to create a
--- task for me to do in the future to make this a bit more clean and only have
--- stuff that makes sense for the api to be in here... but for now.. ia m sorry
local Logger = require("99.logger.logger")
local Tracking = require("99.state.tracking")
local Level = require("99.logger.level")
local ops = require("99.ops")
local Window = require("99.window")
local select_window = require("99.window.select-window")
local StatusWindow = require("99.window.status-window")
local Prompt = require("99.prompt")
local State = require("99.state")
local Extensions = require("99.extensions")
local Agents = require("99.extensions.agents")
local Providers = require("99.providers")

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

--- @class _99.Completion
--- @docs included
--- @field source "cmp" | "blink" | nil
--- @field custom_rules string[]
--- @field files _99.Files.Config?

--- @class _99.Options
--- @docs base
--- @field logger? _99.Logger.Options
--- @field model? string
--- @field in_flight_options? _99.StatusWindow.Opts
--- @field md_files? string[]
--- @field provider? _99.Providers.BaseProvider
--- @field provider_extra_args? string[]
--- @field display_errors? boolean
--- @field auto_add_skills? boolean
--- @field completion? _99.Completion
--- @field tmp_dir? string

--- @type _99.State
local _99_state

--- @alias _99.TraceID number

--- @class _99
--- 99 is an agentic workflow that is meant to meld the current programmers ability
--- with the amazing powers of LLMs.  Instead of being a replacement, its meant to
--- augment the programmer.
---
--- As of now, the direction of 99 is to progress into agentic programming and surfacing
--- of information.  In the beginning and the original youtube video was about replacing
--- specific pieces of code.  The more i use 99 the more i realize the better use is
--- through `search` and `work`
---
--- ### Basic Setup
--- ```lua
--- 	{
--- 		"ThePrimeagen/99",
--- 		config = function()
--- 			local _99 = require("99")
---
---             -- For logging that is to a file if you wish to trace through requests
---             -- for reporting bugs, i would not rely on this, but instead the provided
---             -- logging mechanisms within 99.  This is for more debugging purposes
---             local cwd = vim.uv.cwd()
---             local basename = vim.fs.basename(cwd)
--- 			_99.setup({
---                 -- provider = _99.Providers.ClaudeCodeProvider,  -- default: OpenCodeProvider
--- 				logger = {
--- 					level = _99.DEBUG,
--- 					path = "/tmp/" .. basename .. ".99.debug",
--- 					print_on_error = true,
--- 				},
---                 -- When setting this to something that is not inside the CWD tools
---                 -- such as claude code or opencode will have permission issues
---                 -- and generation will fail refer to tool documentation to resolve
---                 -- https://opencode.ai/docs/permissions/#external-directories
---                 -- https://code.claude.com/docs/en/permissions#read-and-edit
---                 tmp_dir = "./tmp",
---
---                 --- Completions: #rules and @files in the prompt buffer
---                 completion = {
---                     -- I am going to disable these until i understand the
---                     -- problem better.  Inside of cursor rules there is also
---                     -- application rules, which means i need to apply these
---                     -- differently
---                     -- cursor_rules = "<custom path to cursor rules>"
---
---                     --- A list of folders where you have your own SKILL.md
---                     --- Expected format:
---                     --- /path/to/dir/<skill_name>/SKILL.md
---                     ---
---                     --- Example:
---                     --- Input Path:
---                     --- "scratch/custom_rules/"
---                     ---
---                     --- Output Rules:
---                     --- {path = "scratch/custom_rules/vim/SKILL.md", name = "vim"},
---                     --- ... the other rules in that dir ...
---                     ---
---                     custom_rules = {
---                       "scratch/custom_rules/",
---                     },
---
---                     --- Configure @file completion (all fields optional, sensible defaults)
---                     files = {
---                         -- enabled = true,
---                         -- max_file_size = 102400,     -- bytes, skip files larger than this
---                         -- max_files = 5000,            -- cap on total discovered files
---                         -- exclude = { ".env", ".env.*", "node_modules", ".git", ... },
---                     },
---
---                     --- What autocomplete you use.
---                     source = "cmp" | "blink",
---                 },
---
---                 --- WARNING: if you change cwd then this is likely broken
---                 --- ill likely fix this in a later change
---                 ---
---                 --- md_files is a list of files to look for and auto add based on the location
---                 --- of the originating request.  That means if you are at /foo/bar/baz.lua
---                 --- the system will automagically look for:
---                 --- /foo/bar/AGENT.md
---                 --- /foo/AGENT.md
---                 --- assuming that /foo is project root (based on cwd)
--- 				md_files = {
--- 					"AGENT.md",
--- 				},
--- 			})
---
---             -- take extra note that i have visual selection only in v mode
---             -- technically whatever your last visual selection is, will be used
---             -- so i have this set to visual mode so i dont screw up and use an
---             -- old visual selection
---             --
---             -- likely ill add a mode check and assert on required visual mode
---             -- so just prepare for it now
--- 			vim.keymap.set("v", "<leader>9v", function()
--- 				_99.visual()
--- 			end)
---
---             --- if you have a request you dont want to make any changes, just cancel it
--- 			vim.keymap.set("n", "<leader>9x", function()
--- 				_99.stop_all_requests()
--- 			end)
---
--- 			vim.keymap.set("n", "<leader>9s", function()
--- 				_99.search()
--- 			end)
--- 		end,
--- 	},
--- ```
---
--- ### Usage
--- I would highly recommend trying out `search` as its the direction the library is going
---
--- ```lua
--- _99.search()
--- ```
---
--- See search for more details
---
--- @docs base
--- @field setup fun(opts?: _99.Options): nil
--- Sets up _99.  Must be called for this library to work.  This is how we setup
--- in flight request spinners, set default values, get completion to work the
--- way you want it to.
--- @field search fun(opts: _99.ops.SearchOpts): _99.TraceID
--- Performs a search across your project with the prompt you provide and return out a list of
--- locations with notes that will be put into your quick fix list.
--- @field vibe fun(opts?: _99.ops.Opts): _99.TraceID | nil
--- will ask opencode or whatever provider currently being used to perform a vibe
--- session.
--- @field open fun(): nil
--- Opens a selection window for you to select the last interaction to open
--- and display its contents in a way that makes sense for its type.  For
--- search and vibe, it will open the qfix window.  For tutorial, it will open
--- the tutorial window.
--- @field visual fun(opts: _99.ops.Opts): _99.TraceID
--- takes your current selection and sends that along with the prompt provided and replaces
--- your visual selection with the results
--- @field view_logs fun(): nil
--- view_logs allows you to select the request you want to see and then you
--- get to see the logs.
--- @field stop_all_requests fun(): nil
--- stops all in flight requests.  this means that the underlying process will
--- be killed (OpenCode) and any result will be discared
--- @field clear_previous_requests fun(): nil
--- clears all previous search and visual operations
--- @field Extensions _99.Extensions
--- check out Worker for cool abstraction on search and vibe
local _99 = {
  DEBUG = Level.DEBUG,
  INFO = Level.INFO,
  WARN = Level.WARN,
  ERROR = Level.ERROR,
  FATAL = Level.FATAL,
}

--- @param cb fun(context: _99.Prompt, o: _99.ops.Opts?): nil
--- @param name string
--- @param context _99.Prompt
--- @param opts _99.ops.Opts
--- @param capture_content string[] | nil
local function capture_prompt(cb, name, context, opts, capture_content)
  Window.capture_input(name, {
    keymap = {
      [":w"] = "submit",
    },
    content = capture_content,

    --- @param ok boolean
    --- @param response string
    cb = function(ok, response)
      context.logger:debug(
        "capture_prompt",
        "success",
        ok,
        "response",
        response
      )
      if not ok then
        return
      end
      local rules_and_names = Agents.by_name(_99_state.rules, response)
      opts.additional_rules = opts.additional_rules or {}
      for _, r in ipairs(rules_and_names.rules) do
        table.insert(opts.additional_rules, r)
      end
      opts.additional_prompt = response
      context.user_prompt = response
      cb(context, opts)
    end,
    on_load = function()
      Extensions.setup_buffer(_99_state)
    end,
    rules = _99_state.rules,
  })
end

function _99.info()
  local info = {}
  _99_state:refresh_rules()
  table.insert(
    info,
    string.format("Previous Requests: %d", _99_state.tracking:completed())
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

--     elseif #tutorials == 1 then
--       local data = tutorials[1]
--       assert(data, "tutorial is malformed")
--       Window.create_split(data.tutorial, data.buffer, opts)
--       return

--- @param context _99.Prompt
function _99.open_tutorial(context)
  local tutorial = context:tutorial_data()
  Window.create_split(tutorial.tutorial, tutorial.buffer, {
    split_direction = "vertical",
    window_opts = {
      wrap = true,
    },
  })
end

function _99.open()
  local requests = _99_state.tracking:successful()
  local str_requests = Tracking.to_selectable_list(requests)
  select_window(str_requests, function(idx)
    local r = requests[idx]
    assert(r:valid(), "encountered unexpected issue.  malformated data")
    if r.operation == "visual" then
      --- TODO: this is its own work item for being able to have a global mark
      --- section in which i keep track of marks for the lifetime of the
      --- editor and when you close the editor, then it should lose them
      print("visual not supported: i will figure this out... at some point")
    elseif r.operation == "search" or r.operation == "vibe" then
      _99.open_qfix_for_request(r)
    elseif r.operation == "tutorial" then
      _99.open_tutorial(r)
    end
  end)
end

--- @param opts? _99.ops.Opts
--- @return _99.TraceID
function _99.vibe(opts)
  local o = process_opts(opts)
  local context = Prompt.vibe(_99_state)
  if o.additional_prompt then
    context.user_prompt = o.additional_prompt
    ops.vibe(context, o)
  else
    capture_prompt(ops.vibe, "Vibe", context, o)
  end
  return context.xid
end

--- @param opts? _99.ops.SearchOpts
--- @return _99.TraceID
function _99.search(opts)
  local o = process_opts(opts) --[[ @as _99.ops.SearchOpts ]]
  local context = Prompt.search(_99_state)
  if o.additional_prompt then
    context.user_prompt = o.additional_prompt
    ops.search(context, o)
  else
    capture_prompt(ops.search, "Search", context, o)
  end
  return context.xid
end

--- @param opts _99.ops.Opts
function _99.tutorial(opts)
  opts = process_opts(opts)
  local context = Prompt.tutorial(_99_state)
  if opts.additional_prompt then
    context.user_prompt = opts.additional_prompt
    ops.tutorial(context, opts)
  else
    capture_prompt(ops.tutorial, "Tutorial", context, opts)
  end
end

--- @param opts _99.ops.Opts?
--- @return _99.TraceID
function _99.visual(opts)
  opts = process_opts(opts)
  local context = Prompt.visual(_99_state)
  if opts.additional_prompt then
    context.user_prompt = opts.additional_prompt
    ops.over_range(context, opts)
  else
    capture_prompt(ops.over_range, "Visual", context, opts)
  end
  return context.xid
end

function _99.view_logs()
  local requests = _99_state.tracking.history
  local str_requests = Tracking.to_selectable_list(requests)
  select_window(str_requests, function(idx)
    local r = requests[idx]
    local logs = Logger.logs_by_id(r.xid)
    if logs == nil then
      logs = { "No logs found for request: " .. r.xid }
    end
    Window.display_full_screen_message(logs)
  end)
end

--- @param request _99.Prompt
function _99.open_qfix_for_request(request)
  local items = request:qfix_data()
  if #items == 0 then
    print("there are no quickfix items to show")
    return
  end

  vim.fn.setqflist({}, "r", { title = "99 Results", items = items })
  vim.cmd("copen")
end

function _99.stop_all_requests()
  _99_state.tracking:stop_all_requests()
end

function _99.clear_previous_requests()
  _99_state.tracking:clear_history()
end

--- if you touch this function you will be fired
--- @return _99.State
function _99.__get_state()
  return _99_state
end

--- @param opts _99.Options?
function _99.setup(opts)
  opts = opts or {}

  _99_state = State.new(opts)

  local crules = _99_state.completion.custom_rules
  for i, rule in ipairs(crules) do
    local str = expand(rule)
    assert(type(str) == "string", "error parsing rule: path must be a string")
    crules[i] = str
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      _99.stop_all_requests()
      _99_state:sync()
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

  if opts.provider_extra_args then
    assert(
      type(opts.provider_extra_args) == "table",
      "opts.provider_extra_args must be a table"
    )
  end

  if opts.md_files then
    assert(type(opts.md_files) == "table", "opts.md_files is not a table")
    for _, md in ipairs(opts.md_files) do
      _99.add_md_file(md)
    end
  end

  if opts.tmp_dir then
    assert(type(opts.tmp_dir) == "string", "opts.tmp_dir must be a string")
  end
  _99_state.__tmp_dir = opts.tmp_dir

  _99_state.display_errors = opts.display_errors or false
  _99_state:refresh_rules()
  Extensions.init(_99_state)
  Extensions.capture_project_root()

  local sw = StatusWindow.new(_99_state, opts.in_flight_options)
  sw:start()
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

--- @return string
function _99.get_model()
  return _99_state.model
end

--- @return _99.Providers.BaseProvider
function _99.get_provider()
  return _99_state.provider_override or Providers.OpenCodeProvider
end

--- @param provider _99.Providers.BaseProvider
--- @return _99
function _99.set_provider(provider)
  _99_state.provider_override = provider
  if provider._get_default_model then
    _99_state.model = provider._get_default_model()
  end
  return _99
end

function _99.__debug()
  Logger:configure({
    path = nil,
    level = Level.DEBUG,
  })
end

_99.Providers = Providers

--- @class _99.Extensions
--- @field Worker _99.Extensions.Worker
_99.Extensions = {
  Worker = require("99.extensions.work.worker"),
}
return _99
