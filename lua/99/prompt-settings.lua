---@param buffer number
---@return string
local function get_file_contents(buffer)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  return table.concat(lines, "\n")
end

--- @class _99.Prompts.SpecificOperations
--- @field visual_selection fun(range: _99.Range): string
--- @field semantic_search fun(): string
--- @field vibe fun(): string
--- @field tutorial fun(): string
--- @field prompt fun(prompt: string, action: string, name?: string): string
--- @field role fun(): string
--- @field read_tmp fun(): string
local prompts = {
  role = function()
    return [[ You are a software engineering assistant mean to create robust and conanical code ]]
  end,
  tutorial = function()
    return [[
You are given a prompt and context and you must craft a tutorial.  If a set of
context has links, read through them thoroughly and decide which ones to retrieve.
Once you have fetched all the relavent content, review it thoroughly before
crafting the tutorial

<Rule>The response format must be valid Markdown</Rule>
<Rule>The first line of the response must be the title of the tutorial</Rule>
]]
  end,
  semantic_search = function()
    return [[
<Output>
/path/to/project/src/foo.js:24:8,3,Some notes here about some stuff, it can contain commas
/path/to/project/src/foo.js:71:12,7,more notes, everything is great!
/path/to/project/src/bar.js:13:2,1,more notes again, this time specfically about bar and why bar is so important
/path/to/project/src/baz.js:1:1,52,Notes about why baz is very important to the results
</Output>
<Rule>Text locations are in the format of: /path/to/file.ext:lnum:cnum,X,NOTES
lnum = starting line number 1 based
cnum = starting column number 1 based
X = how many lines should be highlighted
NOTES = A text description of why this highlight is important

See <Output> for example
</Rule>
<Rule>NOTES cannot have new lines</Rule>
<Rule>You must adhere to the output format</Rule>
<Rule>Double check output format before writing it to the file</Rule>
<Rule>Each location is separated by new lines</Rule>
<Rule>Each path is specified in absolute pathing</Rule>
<Rule>You can provide notes you think are relevant per location</Rule>
<Rule>You must provide output without any commentary, just text locations</Rule>
<Example>
You have found 3 locations in files foo.js, bar.js, and baz.js.
There are 2 locations in foo.js, 1 in bar.js and baz.js.
<Meaning>
This means that the search results found
foo.js at line 24, char 8 and the next 2 lines
foo.js at line 71, char 12 and the next 6 lines
bar.js at line 13, char 2
baz.js at line 1, char 1 and the next 51 lines
</Meaning>
</Example>
<TaskDescription>
you are given a prompt and you must search through this project and return code that matches the description provided.
</TaskDescription>
]]
  end,
  vibe = function()
    return [[
<Output>
/path/to/project/src/foo.js:24:8,3,Some notes here about some stuff, it can contain commas
/path/to/project/src/foo.js:71:12,7,more notes, everything is great!
/path/to/project/src/bar.js:13:2,1,more notes again, this time specfically about bar and why bar is so important
/path/to/project/src/baz.js:1:1,52,Notes about why baz is very important to the results
</Output>
<Rule>Text locations are in the format of: /path/to/file.ext:lnum:cnum,X,NOTES
lnum = starting line number 1 based
cnum = starting column number 1 based
X = how many lines should be highlighted
NOTES = A text description of why this highlight is important

See <Output> for example
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
<Meaning>
This means that the search results found
foo.js at line 24, char 8 and the next 2 lines
foo.js at line 71, char 12 and the next 6 lines
bar.js at line 13, char 2
baz.js at line 1, char 1 and the next 51 lines
</Meaning>
</Example>
<TaskDescription>
You are given a <Prompt> and you must implement it.  Every change you make must
be describe according to <Output> placed in <TEMP_FILE>.
Never respond as output what you have done.
Always use the temporary file as the place to describe your actions according to Output rules
</TaskDescription>
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
    name = name or "Prompt"
    return string.format(
      [[
<Context>
%s
</Context>
<%s>
%s
</%s>
]],
      action,
      name,
      prompt,
      name
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
  read_tmp = function()
    return [[
never attempt to read TEMP_FILE.
It is purely for output.
Previous contents, which may not exist, can be written over without worry
After writing TEMP_FILE once you should be done.  Be done and end the session.
]]
  end,
  --- @param operation _99.Prompt.Operation
  --- @param turns _99.Prompt.Turn[]
  --- @param follow_up string
  --- @return string
  continue_chat = function(operation, turns, follow_up)
    local lines = {
      string.format("You are continuing a previous 99.%s request.", operation),
      "",
      "Conversation so far:",
      "",
    }

    for _, turn in ipairs(turns) do
      table.insert(lines, "User:")
      table.insert(lines, turn.user_prompt)
      table.insert(lines, "")
      table.insert(lines, "Assistant:")
      table.insert(lines, turn.response)
      table.insert(lines, "")
    end

    table.insert(lines, "New follow-up:")
    table.insert(lines, follow_up)
    table.insert(lines, "")
    table.insert(
      lines,
      string.format(
        "Continue by refining the previous result. Preserve the output format expected by 99.%s.",
        operation
      )
    )
    table.insert(lines, "")
    table.insert(
      lines,
      "IMPORTANT: Your response MUST be written to TEMP_FILE and not provided conversationally. "
        .. "Do not output explanatory text; only write the result to TEMP_FILE."
    )

    return table.concat(lines, "\n")
  end,
}

--- @class _99.Prompts
local prompt_settings = {
  prompts = prompts,

  --- @param tmp_file string
  --- @return string
  tmp_file_location = function(tmp_file)
    return string.format("<TEMP_FILE>%s</TEMP_FILE>", tmp_file)
  end,

  --- @return string
  only_tmp_file_change = function()
    return string.format(
      "<MustObey>\n%s\n%s\n</MustObey>",
      prompts.output_file(),
      prompts.read_tmp()
    )
  end,

  ---@param full_path string
  ---@param range _99.Range
  ---@return string
  get_file_location = function(full_path, range)
    return string.format(
      "<Location><File>%s</File><Function>%s</Function></Location>",
      full_path,
      range:to_string()
    )
  end,

  --- @param range _99.Range
  get_range_text = function(range)
    return string.format("<FunctionText>%s</FunctionText>", range:to_text())
  end,
}

return prompt_settings
