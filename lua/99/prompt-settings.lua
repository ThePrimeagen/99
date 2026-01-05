---@param buffer number
---@return string
local function get_file_contents(buffer)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    return table.concat(lines, "\n")
end

--- @class _99.Prompts.SpecificOperations
--- @field visual_selection fun(range: _99.Range): string
--- @field fill_in_function fun(): string
--- @field implement_function string
local prompts = {
    fill_in_function = function()
        return [[
<Task>Fill in the function body</Task>

<Rules>
1. Preserve the EXACT function signature - do not modify function name, parameters, or return type
2. Only write code INSIDE the function body - never modify anything outside
3. Reuse existing helper functions and utilities from the codebase when applicable
4. Follow any NOTE comments as instructions, then remove them from the final output
5. Follow any TODO comments as instructions, then remove them from the final output
6. Match the code style and conventions used in the surrounding file
</Rules>

<OutputFormat>
Return the COMPLETE function including:
- The full function declaration/signature (unchanged)
- The implemented function body
- The closing of the function

Do NOT return:
- Only the body without the declaration
- Partial implementations
- Explanations or markdown formatting
- Code outside of the function
</OutputFormat>
]]
    end,
    output_file = function()
        return [[
<OutputRules>
1. Write ALL output to TEMP_FILE only
2. Do NOT modify any other files
3. Do NOT include explanations, comments about your changes, or conversational text
4. Write ONLY the requested code/content directly to TEMP_FILE
5. The output must be ready to use as-is without any post-processing
</OutputRules>
]]
    end,
    --- @param prompt string
    --- @param action string
    --- @return string
    prompt = function(prompt, action)
        return string.format(
            [[
%s
<Context>
%s
</Context>
]],
            prompt,
            action
        )
    end,
    visual_selection = function(range)
        return string.format(
            [[
<Task>Replace the selected code with an improved implementation</Task>

<Rules>
1. The selection will be REPLACED with your output - write only the replacement code
2. Follow any NOTE or TODO comments as instructions, then remove them from output
3. Maintain consistency with the surrounding code style and conventions
4. Consider the context of where this code appears in the file
5. Ensure the replacement integrates correctly with the rest of the file
6. Preserve necessary imports, type annotations, and documentation if present
</Rules>

<SelectionInfo>
<Location>%s</Location>
<SelectedCode>
%s
</SelectedCode>
</SelectionInfo>

<FileContext>
%s
</FileContext>

<OutputFormat>
Return ONLY the replacement code that will directly substitute the selection.
Do NOT include:
- Markdown code fences or formatting
- Explanations or comments about changes
- The surrounding unchanged code
- Line numbers
</OutputFormat>
]],
            range:to_string(),
            range:to_text(),
            get_file_contents(range.buffer)
        )
    end,
    -- luacheck: ignore 631
    implement_function = [[
<Task>Implement a new function based on its usage at the cursor location</Task>

<Rules>
1. Analyze the function call to infer the expected signature and behavior
2. Write a complete, working implementation that matches the call site usage
3. Use appropriate parameter names based on the arguments being passed
4. Infer the return type from how the result is used
5. Follow the code style and conventions of the surrounding file
6. Add minimal documentation only if the function's purpose is not obvious
</Rules>

<OutputFormat>
Return ONLY the complete function definition including:
- Function signature with appropriate parameters and types
- The full implementation body
- Proper closing of the function

Do NOT include:
- Markdown code fences or formatting
- Explanations about the implementation
- Multiple alternative implementations
- Import statements (unless absolutely necessary)
</OutputFormat>
]],
    -- luacheck: ignore 631
    read_tmp = "TEMP_FILE is write-only. Never read from it. You may overwrite any existing contents.",
}

--- @class _99.Prompts
local prompt_settings = {
    prompts = prompts,

    --- @param tmp_file string
    --- @return string
    tmp_file_location = function(tmp_file)
        return string.format(
            "<MustObey>\n%s\n%s\n</MustObey>\n<TEMP_FILE>%s</TEMP_FILE>",
            prompts.output_file(),
            prompts.read_tmp,
            tmp_file
        )
    end,

    ---@param context _99.RequestContext
    ---@return string
    get_file_location = function(context)
        context.logger:assert(
            context.range,
            "get_file_location requires range specified"
        )
        return string.format(
            "<Location><File>%s</File><Function>%s</Function></Location>",
            context.full_path,
            context.range:to_string()
        )
    end,

    --- @param range _99.Range
    get_range_text = function(range)
        return string.format("<FunctionText>%s</FunctionText>", range:to_text())
    end,
}

return prompt_settings
