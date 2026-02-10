---@param buffer number
---@return string
local function get_file_contents(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  return table.concat(lines, "\n")
end

--- @class _99.Prompts.SpecificOperations
--- @field visual_selection fun(range: _99.Range): string
--- @field semantic_search fun(): string
--- @field prompt fun(prompt: string, action: string, name?: string): string
--- @field role fun(): string
--- @field read_tmp fun(): string
local prompts = {
  role = function()
    return [[ You are a software engineering assistant meant to create robust and canonical code ]]
  end,
  semantic_search = function()
    return [[
you are given a prompt and you must search through this project and return code that matches the description provided.
<Rule>You must provide output without any commentary, just text locations</Rule>
<Rule>Text locations are in the format of: /path/to/file.ext:lnum:cnum,X,NOTES
lnum = starting line number 1 based
cnum = starting column number 1 based
X = how many lines should be highlighted
NOTES = A text description of why this highlight is important
</Rule>
<Rule>NOTES cannot have new lines</Rule>
<Rule>You must adhere to the output format</Rule>
<Rule>Double check output format before writing it to the file</Rule>
<Rule>Each location is separated by new lines</Rule>
<Rule>Each path is specified in absolute pathing</Rule>
<Rule>You can provide notes you think are relevant per location</Rule>
<Example>
You have found 3 locations in files foo.js, bar.js, and baz.js.
There are 2 locations in foo.js, 1 in bar.js and baz.js.
<Output>
/path/to/project/src/foo.js:24:8,3,Some notes here about some stuff, it can contain commas
/path/to/project/src/foo.js:71:12,7,more notes, everything is great!
/path/to/project/src/bar.js:13:2,1,more notes again, this time specfically about bar and why bar is so important
/path/to/project/src/baz.js:1:1,52,Notes about why baz is very important to the results
</Output>
<Meaning>
This means that the search results found
foo.js at line 24, char 8 and the next 2 lines
foo.js at line 71, char 12 and the next 6 lines
bar.js at line 13, char 2
baz.js at line 1, char 1 and the next 51 lines
</Meaning>
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
  --- @param name? string defaults to DIRECTIONS
  --- @return string
  prompt = function(prompt, action, name)
    name = name or "DIRECTIONS"
    return string.format(
      [[
<%s>
%s
</%s>
<Context>
%s
</Context>
]],
      name,
      prompt,
      name,
      action
    )
  end,
  visual_selection = function(range)
    return string.format(
      [[
You receive a selection in neovim that you need to replace with new code.
The selection's contents may contain notes, incorporate the notes every time if there are some.
consider the context of the selection and what you are supposed to be implementing
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
  read_tmp = function()
    return [[
never attempt to read TEMP_FILE.
It is purely for output.
Previous contents, which may not exist, can be written over without worry
After writing TEMP_FILE once you should be done.  Be done and end the session.
]]
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
      prompts.read_tmp(),
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
