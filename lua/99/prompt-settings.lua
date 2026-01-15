---@param buffer number
---@return string
local function get_file_contents(buffer)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    return table.concat(lines, "\n")
end

local function get_lang(context)
    if not context or not context._99 then
        return "en"
    end
    -- Intelligent part: check buffer local spelllang first
    local buf_spelllang = vim.api.nvim_get_option_value("spelllang", { buf = context.buffer })
    if buf_spelllang and buf_spelllang ~= "" and buf_spelllang ~= "en" then
        return buf_spelllang
    end
    return context._99.writer_language or "en"
end

local function create_prompts(role_text, visual_text, completion_text, implement_text)
    local function resolve(val, ...)
        if type(val) == "function" then
            return val(...)
        end
        return val
    end

    return {
        role = function(context)
            return resolve(role_text, get_lang(context))
        end,
        fill_in_function = function(context)
            return resolve(completion_text, get_lang(context))
        end,
        implement_function = function(context)
            return resolve(implement_text, get_lang(context))
        end,
        output_file = function()
            return [[
NEVER alter any file other than TEMP_FILE.
never provide the requested changes as conversational output.
ONLY provide requested changes by writing the change to TEMP_FILE
]]
        end,
        --- @param prompt string
        --- @param action string
        --- @return string
        prompt = function(prompt, action)
            return string.format(
                [[
<DIRECTIONS>
%s
</DIRECTIONS>
<Context>
%s
</Context>
]],
                prompt,
                action
            )
        end,
        visual_selection = function(range, context)
            return string.format(
                [[
%s
<SELECTION_LOCATION>
%s
</SELECTION_LOCATION>
<SELECTION_CONTENT>
%s
</SELECTION_CONTENT>
<FILE_CONTAINING_SELECTION>
%s
</FILE_CONTAINING_SELECTION>
]],
                resolve(visual_text, get_lang(context)),
                range:to_string(),
                range:to_text(),
                get_file_contents(range.buffer)
            )
        end,
        -- luacheck: ignore 631
        read_tmp = "never attempt to read TEMP_FILE.  It is purely for output.  Previous contents, which may not exist, can be written over without worry",
    }
end

local code_prompts = create_prompts(
    "You are a software engineering assistant mean to create robust and conanical code",
    "You receive a selection in neovim that you need to replace with new code.\nThe selection's contents may contain notes, incorporate the notes every time if there are some.\nconsider the context of the selection and what you are suppose to be implementing",
    [[
You have been given a function change.
Create the contents of the function.
If the function already contains contents, use those as context
Check the contents of the file you are in for any helper functions or context

if there are DIRECTIONS, follow those when changing this function.  Do not deviate
]],
    "You have been given a function call.  Implement the function that is being called"
)

local writer_prompts = create_prompts(
    function(lang)
        return string.format("You are a professional writing assistant and editor. Your goal is to improve the quality, clarity, and flow of the text provided in %s, while maintaining its original intent and tone. If the input is poetry, your primary objective is to enhance the lyrical quality while strictly preserving the rhyme scheme and meter.", lang)
    end,
    function(lang)
        return string.format("You receive a selection of text in neovim (language: %s) that you need to improve or edit. If this is a poem, ensure the rhymes remain intact.\nThe selection's contents may contain notes, incorporate the notes every time if there are some.\nconsider the context of the selection and what you are suppose to be improving", lang)
    end,
    function(lang)
        return string.format([[
You have been given a text completion task in %s.
Improve and complete the text based on the surrounding context.
If the text already contains contents, use those as context.

If the text appears to be a POEM or has a rhythmic/rhyming structure, you MUST preserve the rhyme scheme and meter while improving the vocabulary or flow.

if there are DIRECTIONS, follow those when changing this text. Do not deviate.
]], lang)
    end,
    function(lang)
        return string.format("You have been given a reference or a title in %s. Write a paragraph or section about it.", lang)
    end
)

--- @class _99.Prompts
local prompt_settings = {
    modes = {
        code = code_prompts,
        writer = writer_prompts,
    },

    --- @param tmp_file string
    --- @param prompts table
    --- @return string
    tmp_file_location = function(tmp_file, prompts)
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
