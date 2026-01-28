---@param buffer number
---@return string
local function get_file_contents(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  return table.concat(lines, "\n")
end

--- @class _99.Prompts.SpecificOperations
--- @field visual_selection fun(range: _99.Range): string
--- @field fill_in_function fun(): string
local prompts = {
  role = function()
    return [[ You are a software engineering assistant mean to create robust and conanical code ]]
  end,
  fill_in_function = function()
    return [[
You have been given a function change.
Create the contents of the function.
If the function already contains contents, use those as context
Check the contents of the file you are in for any helper functions or context
Your response should be the complete function, including signature

<Example>
<Input>
export function fizz_buzz(count: number): void {
}
</Input>
<Output>
function fizz_buzz(count: number): void {
  for (let i = 1; i <= count; i++) {
    if (i % 15 === 0) {
      console.log("FizzBuzz");
    } else if (i % 3 === 0) {
      console.log("Fizz");
    } else if (i % 5 === 0) {
      console.log("Buzz");
    } else {
      console.log(i);
    }
  }
}
</Output>
<Notes>
* notice that the output did not include the export statement
* only return the function
</Notes>
</Example>


if there are DIRECTIONS, follow those when changing this function.  Do not deviate
]]
  end,
  output_file = function()
    return [[
NEVER alter any file other than TEMP_FILE.
never provide the requested changes as conversational output. Return only the code.
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
  visual_selection = function(range)
    return string.format(
      [[
You receive a selection in neovim that you need to replace with new code.
The selection's contents may contain notes, incorporate the notes every time if there are some.
consider the context of the selection and what you are suppose to be implementing
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
      range:to_string(),
      range:to_text(),
      get_file_contents(range.buffer)
    )
  end,
  -- luacheck: ignore 631
  read_tmp = "never attempt to read TEMP_FILE.  It is purely for output.  Previous contents, which may not exist, can be written over without worry",

  --- @param path string
  --- @param line_num number
  --- @param line_text string
  --- @param user_request string
  --- @return string
  refactor = function(path, line_num, line_text, user_request)
    return string.format(
      [[Apply this change to the following line of code:

File: %s (line %d)
```
%s
```

User request: %s

Return ONLY the updated line of code, nothing else.]],
      path,
      line_num,
      line_text,
      user_request
    )
  end,
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
