local Point = require("99.geo").Point
local nsid = vim.api.nvim_create_namespace("99.marks")

--- @class _99.Mark.Text
--- @field text string
--- @field hlgroup string

--- @class _99.Mark
--- @field id any -- whatever extmark returns
--- @field buffer number
--- @field nsid any
local Mark = {}
Mark.__index = Mark

--- @param range _99.Range
--- @return _99.Mark
function Mark.mark_above_range(range)
  local buffer = range.buffer
  local start = range.start
  local line, _ = start:to_vim()
  local above = line == 0 and line or line - 1

  -- luacheck: ignore
  local id = nil
  if above == line then
    id = vim.api.nvim_buf_set_extmark(buffer, nsid, above, 0, {})
  else
    local lines = vim.api.nvim_buf_get_lines(buffer, above, above + 1, false)
    local text = lines[1]
    if text then
      local ending = #text
      id = vim.api.nvim_buf_set_extmark(buffer, nsid, above, ending, {})
    end
    -- If text is nil, id remains nil and is_valid() will return false
  end

  return setmetatable({
    id = id,
    buffer = buffer,
    nsid = nsid,
  }, Mark)
end

--- @param range _99.Range
--- @return _99.Mark
--- @return _99.Mark
function Mark.mark_range(range)
  local buffer = range.buffer
  return Mark.mark_point(buffer, range.start),
    Mark.mark_point(buffer, range.end_)
end

--- @return boolean
function Mark:is_valid()
  if not self.id then
    return false
  end
  local pos =
    vim.api.nvim_buf_get_extmark_by_id(self.buffer, self.nsid, self.id, {})
  return #pos > 0
end

--- @param buffer number
--- @param point _99.Point
--- @return _99.Mark
function Mark.mark_point(buffer, point)
  local line, col = point:to_vim()
  local id = vim.api.nvim_buf_set_extmark(buffer, nsid, line, col, {})

  return setmetatable({
    id = id,
    buffer = buffer,
    nsid = nsid,
  }, Mark)
end

--- @param buffer number
--- @param func _99.treesitter.Function
--- @return _99.Mark
function Mark.mark_above_func(buffer, func)
  local start = func.function_range.start
  local line, col = start:to_vim()

  line = line - 1
  if line < 0 then
    col = 0
    line = 0
  end

  local id = vim.api.nvim_buf_set_extmark(buffer, nsid, line, col, {})

  return setmetatable({
    id = id,
    buffer = buffer,
    nsid = nsid,
  }, Mark)
end

---@param buffer number
---@param range _99.Range
---@return _99.Mark
function Mark.mark_end_of_range(buffer, range)
  local end_ = range.end_
  local line, col = end_:to_vim()
  local id = vim.api.nvim_buf_set_extmark(buffer, nsid, line, col + 1, {})

  return setmetatable({
    id = id,
    buffer = buffer,
    nsid = nsid,
  }, Mark)
end

--- @param buffer number
--- @param func _99.treesitter.Function
--- @return _99.Mark
function Mark.mark_func_body(buffer, func)
  local start = func.function_range.start
  local line, col = start:to_vim()
  local id = vim.api.nvim_buf_set_extmark(buffer, nsid, line, col, {})

  return setmetatable({
    id = id,
    buffer = buffer,
    nsid = nsid,
  }, Mark)
end

--- @param lines string[]
function Mark:set_virtual_text(lines)
  if not self.id then
    return
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(self.buffer, nsid, self.id, {})
  assert(#pos > 0, "extmark is broken.  it does not exist")
  local row, col = pos[1], pos[2]

  local formatted_lines = {}
  for _, line in ipairs(lines) do
    table.insert(formatted_lines, {
      { line, "Comment" },
    })
  end

  vim.api.nvim_buf_set_extmark(self.buffer, nsid, row, col, {
    id = self.id,
    virt_lines = formatted_lines,
  })
end

--- @param text string
function Mark:set_text_at_mark(text)
  local point = Point.from_mark(self)
  local row, col = point:to_vim()
  local lines = vim.split(text, "\n")
  vim.api.nvim_buf_set_text(self.buffer, row, col, row, col, lines)
end

function Mark:delete()
  if not self.id then
    return
  end
  vim.api.nvim_buf_del_extmark(self.buffer, nsid, self.id)
end

return Mark
