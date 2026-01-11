local Logger = require("99.logger.logger")
local Level = require("99.logger.level")
local ops = require("99.ops")
local Languages = require("99.language")
local Window = require("99.window")
local get_id = require("99.id")
local RequestContext = require("99.request-context")
local Range = require("99.geo").Range

--- @alias _99.Cleanup fun(): nil

--- @class _99.StateProps
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field languages string[]
--- @field display_errors boolean
--- @field provider_override _99.Provider?
--- @field __active_requests _99.Cleanup[]
--- @field __view_log_idx number

--- @return _99.StateProps
local function create_99_state()
    return {
        model = "opencode/claude-sonnet-4-5",
        md_files = {},
        prompts = require("99.prompt-settings"),
        ai_stdout_rows = 3,
        languages = { "lua", "go", "java", "python", "ruby", "rust", "c" },
        display_errors = false,
        __active_requests = {},
        __view_log_idx = 1,
    }
end

--- @class _99.Options
--- @field logger _99.Logger.Options?
--- @field model string?
--- @field md_files string[]?
--- @field provider _99.Provider?
--- @field debug_log_prefix string?
--- @field display_errors? boolean

--- unanswered question -- will i need to queue messages one at a time or
--- just send them all...  So to prepare ill be sending around this state object
--- @class _99.State
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field languages string[]
--- @field display_errors boolean
--- @field provider_override _99.Provider?
--- @field __active_requests _99.Cleanup[]
--- @field __view_log_idx number
local _99_State = {}
_99_State.__index = _99_State

--- @return _99.State
function _99_State.new()
    local props = create_99_state()
    ---@diagnostic disable-next-line: return-type-mismatch
    return setmetatable(props, _99_State)
end

local _active_request_id = 0
---@param clean_up _99.Cleanup
---@return number
function _99_State:add_active_request(clean_up)
    _active_request_id = _active_request_id + 1
    Logger:debug("adding active request", "id", _active_request_id)
    self.__active_requests[_active_request_id] = clean_up
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
    logger:assert(
        r,
        "there is no active request for id.  implementation broken"
    )
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

--- @param operation_name string
--- @return _99.RequestContext
local function get_context(operation_name)
    local trace_id = get_id()
    local context = RequestContext.from_current_buffer(_99_state, trace_id)
    context.logger:debug("99 Request", "method", operation_name)
    return context
end

function _99.info()
    local info = {}
    table.insert(
        info,
        string.format("Agent Files: %s", table.concat(_99_state.md_files, ", "))
    )
    table.insert(info, string.format("Model: %s", _99_state.model))
    table.insert(
        info,
        string.format("AI Stdout Rows: %d", _99_state.ai_stdout_rows)
    )
    table.insert(
        info,
        string.format("Display Errors: %s", tostring(_99_state.display_errors))
    )
    table.insert(
        info,
        string.format("Active Requests: %d", _99_state:active_request_count())
    )
    Window.display_centered_message(info)
end

function _99.fill_in_function_prompt()
    local context = get_context("fill-in-function-with-prompt")
    context.logger:debug("start")
    Window.capture_input(function(success, response)
        context.logger:debug(
            "capture_prompt",
            "success",
            success,
            "response",
            response
        )
        if success then
            ops.fill_in_function(context, response)
        end
    end, {})
end

function _99.fill_in_function()
    ops.fill_in_function(get_context("fill_in_function"))
end

function _99.visual_prompt()
    local context = get_context("over-range-with-prompt")
    context.logger:debug("start")
    Window.capture_input(function(success, response)
        context.logger:debug(
            "capture_prompt",
            "success",
            success,
            "response",
            response
        )
        if success then
            _99.visual(response)
        end
    end, {})
end

--- @param prompt string?
--- @param context _99.RequestContext?
function _99.visual(prompt, context)
    --- TODO: Talk to teej about this.
    --- Visual selection marks are only set in place post visual selection.
    --- that means for this function to work i must escape out of visual mode
    --- which i dislike very much.  because maybe you dont want this
    set_selection_marks()

    context = context or get_context("over-range")
    local range = Range.from_visual_selection()
    ops.over_range(context, range, prompt)
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

function _99.__debug_ident()
    ops.debug_ident(_99_state)
end

function _99.stop_all_requests()
    for _, clean_up in pairs(_99_state.__active_requests) do
        clean_up()
    end
    _99_state.__active_requests = {}
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

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            _99.stop_all_requests()
        end,
    })

    Logger:configure(opts.logger)

    if opts.model then
        assert(type(opts.model) == "string", "opts.model is not a string")
        _99_state.model = opts.model
    end

    if opts.md_files then
        assert(type(opts.md_files) == "table", "opts.md_files is not a table")
        for _, md in ipairs(opts.md_files) do
            _99.add_md_file(md)
        end
    end

    _99_state.display_errors = opts.display_errors or false

    Languages.initialize(_99_state)
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

return _99
