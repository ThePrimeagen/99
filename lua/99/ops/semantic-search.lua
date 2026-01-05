local Request = require("99.request")
local RequestStatus = require("99.ops.request_status")
local make_clean_up = require("99.ops.clean-up")
local Window = require("99.window")

--- Parse the AI response to extract file locations
--- Expected format: file:line:col or file:line
--- @param response string
--- @return table[] quickfix items
local function parse_response_to_qf_items(response)
    local items = {}
    local lines = vim.split(response, "\n")

    for _, line in ipairs(lines) do
        -- Skip empty lines and lines that look like markdown headers/text
        if line ~= "" and not line:match("^#") and not line:match("^%s*$") then
            -- Try to match patterns like:
            -- file:line:col:text
            -- file:line:col
            -- file:line
            local file, lnum, col, text =
                line:match("^([^:]+):(%d+):(%d+):?(.*)")
            if not file then
                file, lnum = line:match("^([^:]+):(%d+)")
            end

            if file and lnum then
                -- Check if file exists (could be relative or absolute)
                local full_path = file
                if not vim.fn.filereadable(file) then
                    -- Try with cwd
                    local cwd_path = vim.fn.getcwd() .. "/" .. file
                    if vim.fn.filereadable(cwd_path) == 1 then
                        full_path = cwd_path
                    end
                end

                table.insert(items, {
                    filename = full_path,
                    lnum = tonumber(lnum) or 1,
                    col = tonumber(col) or 1,
                    text = text or line,
                })
            end
        end
    end

    return items
end

--- @param context _99.RequestContext
--- @param prompt string
local function semantic_search(context, prompt)
    local logger = context.logger:set_area("semantic_search")
    logger:debug("starting semantic search", "prompt", prompt)

    local request = Request.new(context)

    -- Build the search prompt with instructions for the AI to return file locations
    -- luacheck: ignore 631
    local search_prompt = string.format(
        [[
You are a code search assistant. Search the codebase and return relevant files with line numbers.

IMPORTANT: Your response MUST be ONLY in this exact format, one per line:
filepath:line_number:column_number:brief description

Do not include any other text, explanation, or markdown formatting.
Do not include code blocks or backticks.
Just output the file locations, nothing else.

If you find no relevant files, output: NO_RESULTS_FOUND

<Query>
%s
</Query>

Search the codebase for files relevant to this query and return their locations.
]],
        prompt
    )

    request:add_prompt_content(search_prompt)

    -- Use a centered window to show status
    local win, config = Window.create_centered_window()
    vim.api.nvim_buf_set_lines(
        win.buf_id,
        0,
        -1,
        false,
        { "Searching codebase...", "", "Query: " .. prompt }
    )

    local clean_up = make_clean_up(context, function()
        request:cancel()
        Window.clear_active_popups()
    end)

    request:start({
        on_stdout = function(line)
            logger:debug("semantic_search#on_stdout", "line", line)
        end,
        on_stderr = function(line)
            logger:debug("semantic_search#on_stderr", "line", line)
        end,
        on_complete = function(status, response)
            vim.schedule(function()
                clean_up()

                if status == "cancelled" then
                    logger:debug("semantic search was cancelled")
                    Window.display_cancellation_message("Search cancelled")
                    return
                end

                if status == "failed" then
                    logger:error(
                        "semantic search failed",
                        "error response",
                        response or "no response provided"
                    )
                    if context._99.display_errors then
                        Window.display_error(
                            "Semantic search failed\n"
                                .. (response or "No error details provided")
                        )
                    end
                    return
                end

                -- Parse response and populate quickfix list
                if response == "NO_RESULTS_FOUND" or response == "" then
                    vim.notify(
                        "99: No relevant files found for query",
                        vim.log.levels.INFO
                    )
                    return
                end

                local qf_items = parse_response_to_qf_items(response)

                if #qf_items == 0 then
                    vim.notify(
                        "99: Could not parse any file locations from response",
                        vim.log.levels.WARN
                    )
                    logger:debug(
                        "semantic_search: no items parsed",
                        "response",
                        response
                    )
                    return
                end

                -- Set the quickfix list
                vim.fn.setqflist({}, " ", {
                    title = "99 Semantic Search: " .. prompt,
                    items = qf_items,
                })

                -- Open the quickfix window
                vim.cmd.copen()

                logger:info(
                    "semantic search completed",
                    "items_found",
                    #qf_items
                )
                vim.notify(
                    string.format(
                        "99: Found %d relevant location(s)",
                        #qf_items
                    ),
                    vim.log.levels.INFO
                )
            end)
        end,
    })
end

return semantic_search
