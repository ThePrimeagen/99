local geo = require("99.geo")
local Point = geo.Point
local Request = require("99.request")
local Mark = require("99.ops.marks")
local editor = require("99.editor")
local RequestStatus = require("99.ops.request_status")
local Window = require("99.window")
local make_clean_up = require("99.ops.clean-up")

--- @param context _99.RequestContext
--- @param res string
local function update_file_with_changes(context, res)
    local buffer = context.buffer
    local mark = context.marks.function_location
    local logger =
        context.logger:set_area("fill_in_function#update_file_with_changes")

    logger:assert(
        mark and buffer,
        "mark and buffer have to be set on the location object"
    )
    logger:assert(mark:is_valid(), "mark is no longer valid")

    local func_start = Point.from_mark(mark)
    local ts = editor.treesitter
    local func = ts.containing_function(context, func_start)

    logger:assert(
        func,
        "update_file_with_changes: unable to find function at mark location"
    )

    local lines = vim.split(res, "\n")

    -- lua docs ignore next error, func being tested already in assert
    -- TODO: fix this?
    func:replace_text(lines)
end

--- @param context _99.RequestContext
--- @param additional_prompt string?
local function fill_in_function(context, additional_prompt)
    local logger = context.logger:set_area("fill_in_function")
    local ts = editor.treesitter
    local buffer = vim.api.nvim_get_current_buf()
    local cursor = Point:from_cursor()
    local func = ts.containing_function(context, cursor)

    if not func then
        logger:fatal("fill_in_function: unable to find any containing function")
        return
    end

    context.range = func.function_range

    local virt_line_count = context._99.ai_stdout_rows
    if virt_line_count >= 0 then
        context.marks.function_location = Mark.mark_func_body(buffer, func)
    end

    local request = Request.new(context)
    local full_prompt = context._99.prompts.prompts.fill_in_function(context)
    if additional_prompt then
        full_prompt =
            context._99.prompts.prompts.prompt(additional_prompt, full_prompt)
    end
    request:add_prompt_content(full_prompt)

    local request_status = RequestStatus.new(
        250,
        context._99.ai_stdout_rows,
        "Loading",
        context.marks.function_location
    )
    request_status:start()

    local clean_up = make_clean_up(context, function()
        context:clear_marks()
        request:cancel()
        request_status:stop()
    end)

    request:start({
        on_stdout = function(line)
            request_status:push(line)
        end,
        on_complete = function(status, response)
            logger:info("on_complete", "status", status, "response", response)
            vim.schedule(clean_up)

            if status == "failed" then
                if context._99.display_errors then
                    Window.display_error(
                        "Error encountered while processing fill_in_function\n"
                            .. (
                                response
                                or "No Error text provided.  Check logs"
                            )
                    )
                end
                logger:error(
                    "unable to fill in function, enable and check logger for more details"
                )
            elseif status == "cancelled" then
                logger:debug("fill_in_function was cancelled")
                -- TODO: small status window here
            elseif status == "success" then
                update_file_with_changes(context, response)
            end
        end,
        on_stderr = function(line)
            logger:debug("fill_in_function#on_stderr", "line", line)
        end,
    })
end

return fill_in_function
