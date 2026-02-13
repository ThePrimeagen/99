local Logger = require("99.logger.logger")
local utils = require("99.utils")
local random_file = utils.random_file

--- @class _99.RequestContext
--- @field md_file_names string[]
--- @field ai_context string[]
--- @field model string
--- @field tmp_file string
--- @field full_path string
--- @field buffer number
--- @field file_type string
--- @field marks table<string, _99.Mark>
--- @field logger _99.Logger
--- @field xid number
--- @field range _99.Range?
--- @field operation string?
--- @field _99 _99.State
local RequestContext = {}
RequestContext.__index = RequestContext

--- @param _99 _99.State
--- @param xid number
--- @return _99.RequestContext
function RequestContext.from_current_buffer(_99, xid)
  local buffer = vim.api.nvim_get_current_buf()
  local full_path = vim.api.nvim_buf_get_name(buffer)
  local file_type = vim.bo[buffer].ft

  if file_type == "typescriptreact" then
    file_type = "typescript"
  end

  local mds = {}
  for _, md in ipairs(_99.md_files) do
    table.insert(mds, md)
  end

  local tmp_dir = _99.tmp_dir
  if tmp_dir then
    tmp_dir = vim.fn.expand(tmp_dir)
  end

  return setmetatable({
    _99 = _99,
    md_file_names = mds,
    ai_context = {},
    tmp_file = random_file(tmp_dir),
    buffer = buffer,
    full_path = full_path,
    file_type = file_type,
    logger = Logger:set_id(xid),
    xid = xid,
    model = _99.model,
    marks = {},
  }, RequestContext)
end

--- @param md_file_name string
--- @return self
function RequestContext:add_md_file_name(md_file_name)
  table.insert(self.md_file_names, md_file_name)
  return self
end

--- TODO: Dedupe any rules that have already been added
--- @param rules (_99.Agents.Rule | string)[]
function RequestContext:add_agent_rules(rules)
  for _, rule in ipairs(rules) do
    -- Handle both string paths and rule objects
    self.logger:debug("adding custom rule to agent", "rule", rule)
    local file_path = rule.absolute_path or rule.path
    local ok, file = pcall(io.open, file_path, "r")
    if ok and file then
      local content = file:read("*a")
      file:close()
      self.logger:info(
        "Context#adding agent file to the context",
        "agent_path",
        rule.path
      )
      table.insert(
        self.ai_context,
        string.format(
          [[
<%s>
%s
</%s>]],
          rule.name,
          content,
          rule.name
        )
      )
    else
      self.logger:debug("unable to read agent rule", "rule", rule)
    end
  end
end

--- @param refs _99.Reference[]
function RequestContext:add_references(refs)
  for _, ref in ipairs(refs) do
    self.logger:debug("adding reference to context")
    table.insert(self.ai_context, ref.content)
  end
end

function RequestContext:_read_md_files()
  local cwd = vim.uv.cwd()
  local dir = vim.fn.fnamemodify(self.full_path, ":h")

  while dir:find(cwd, 1, true) == 1 do
    for _, md_file_name in ipairs(self.md_file_names) do
      local md_path = dir .. "/" .. md_file_name
      local file = io.open(md_path, "r")
      if file then
        local content = file:read("*a")
        file:close()
        self.logger:info(
          "Context#adding md file to the context",
          "md_path",
          md_path
        )
        table.insert(self.ai_context, content)
      end
    end

    if dir == cwd then
      break
    end

    dir = vim.fn.fnamemodify(dir, ":h")
  end
end

--- @return string[]
function RequestContext:content()
  return self.ai_context
end

--- @param prompt string
function RequestContext:save_prompt(prompt)
  local prompt_file = self.tmp_file .. "-prompt"

  local dir = vim.fs.dirname(prompt_file)

  if dir and not vim.uv.fs_stat(dir) then
    pcall(vim.uv.fs_mkdir, dir, 493)
  end

  local file = io.open(prompt_file, "w")
  if file then
    file:write(prompt)
    file:close()
    self.logger:debug("saved prompt to file", "path", prompt_file)
  else
    self.logger:error("failed to save prompt", "path", prompt_file)
  end
end

--- @return self
function RequestContext:finalize()
  self:_read_md_files()
  if self.range then
    table.insert(self.ai_context, self._99.prompts.get_file_location(self))
    table.insert(self.ai_context, self._99.prompts.get_range_text(self.range))
  end
  table.insert(
    self.ai_context,
    self._99.prompts.tmp_file_location(self.tmp_file)
  )
  return self
end

function RequestContext:clear_marks()
  for _, mark in pairs(self.marks) do
    mark:delete()
  end
end

return RequestContext
