--- TODO: rewrite : functions to . functions where they dont referencegeo
--- self.
---
local project_row = 100000000

--- @param point_or_row _99.Point | number
--- @param col number | nil
--- @return number
local function project(point_or_row, col)
  if type(point_or_row) == "number" then
    return point_or_row * project_row + col
  end
  return point_or_row.row * project_row + point_or_row.col
end

--- stores all values as 1 based
--- @class _99.Point
--- @field row number
--- @field col number
local Point = {}
Point.__index = Point

function Point:to_string()
  return string.format("point(%d,%d)", self.row, self.col)
end

--- @param buffer number
--- @return string
function Point:get_text_line(buffer)
  local r, _ = self:to_vim()
  return vim.api.nvim_buf_get_lines(buffer, r, r + 1, true)[1]
end

--- @param buffer number
--- @param text string
function Point:set_text_line(buffer, text)
  local r, _ = self:to_vim()
  vim.api.nvim_buf_set_lines(buffer, r, r + 1, false, { text })
end

function Point:update_to_end_of_line()
  self.col = vim.fn.col("$") + 1
  local r, c = self:to_one_zero_index()
  vim.api.nvim_win_set_cursor(0, { r, c })
end

--- 1 based point
--- @param row number
--- @param col number
--- @return _99.Point
function Point:from_1_based(row, col)
  assert(type(row) == "number", "expected row to be a number")
  assert(type(col) == "number", "expected col to be a number")
  return setmetatable({
    row = row,
    col = col,
  }, self)
end

--- 0 based point
--- @param row number
--- @param col number
--- @return _99.Point
function Point.from_0_based(row, col)
  assert(type(row) == "number", "expected row to be a number")
  assert(type(col) == "number", "expected col to be a number")
  return setmetatable({
    row = row + 1,
    col = col + 1,
  }, Point)
end

function Point:from_cursor()
  local point = setmetatable({
    row = 0,
    col = 0,
  }, self)

  --- NOTE: win_get_cursor 1, 0 based return
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row, cursor_col = cursor[1], cursor[2]
  point.row = cursor_row
  point.col = cursor_col + 1
  return point
end

--- Point from nvim_buf_get_extmark_by_id returns which is 0 based
--- @param mark _99.Mark
function Point.from_extmark(mark)
  local buffer = mark.buffer
  local ns_id = mark.nsid
  local mark_id = mark.id
  local row, col = vim.api.nvim_buf_get_extmark_by_id(buffer, ns_id, mark_id)
  return setmetatable({
    row = row + 1,
    col = col + 1,
  }, Point)
end

--- @param row number
---@param col number
--- @return _99.Point
function Point:from_ts_point(row, col)
  return setmetatable({
    row = row + 1,
    col = col + 1,
  }, self)
end

--- @param lsp_point {character: number, line: number}
function Point.from_lsp_point(lsp_point)
  return setmetatable({
    row = lsp_point.line + 1,
    col = lsp_point.character + 1,
  }, Point)
end

--- stores all 2 points
--- @param range _99.Range
--- @return boolean
function Point:in_ts_range(range)
  return range:contains(self)
end

--- vim.api.nvim_buf_get_text uses 0 based row and col
--- @return number, number
function Point:to_lua()
  return self.row, self.col
end

--- @return number, number
function Point:to_lsp()
  return self.row - 1, self.col - 1
end

--- vim.api.nvim_buf_get_text uses 0 based row and col
--- @return number, number
function Point:to_vim()
  return self.row - 1, self.col - 1
end

function Point:to_one_zero_index()
  return self.row, self.col - 1
end

--- treesitter uses 0 based row and col
--- @return number, number
function Point:to_ts()
  return self.row - 1, self.col - 1
end

--- @param point _99.Point
--- @return boolean
function Point:gt(point)
  return project(self) > project(point)
end

--- @param point _99.Point
--- @return boolean
function Point:lt(point)
  return project(self) < project(point)
end

--- @param point _99.Point
--- @return boolean
function Point:lte(point)
  return project(self) <= project(point)
end

--- @param point _99.Point
--- @return boolean
function Point:gte(point)
  return project(self) >= project(point)
end

--- @param point _99.Point
--- @return boolean
function Point:eq(point)
  return project(self) == project(point)
end

--- @param point _99.Point
--- @return _99.Point
function Point:add(point)
  return Point:from_1_based(self.row + point.row, self.col + point.col)
end

--- @param point _99.Point
--- @return _99.Point
function Point:sub(point)
  return Point:from_1_based(self.row - point.row, self.col - point.col)
end

--- @param mark _99.Mark
--- @return _99.Point
function Point.from_mark(mark)
  if not mark.id then
    return Point:from_1_based(0, 0)
  end
  --- buf extmark by id is a 0 based api
  local pos =
    vim.api.nvim_buf_get_extmark_by_id(mark.buffer, mark.nsid, mark.id, {})

  return setmetatable({
    row = pos[1] + 1,
    col = pos[2] + 1,
  }, Point)
end

function Point.zero()
  return Point.from_0_based(0, 0)
end

--- @class _99.Range
--- @field start _99.Point
--- @field end_ _99.Point
--- @field buffer number
local Range = {}
Range.__index = Range

---@param buffer number
--- @param start _99.Point
---@param end_ _99.Point
function Range:new(buffer, start, end_)
  return setmetatable({
    start = start,
    end_ = end_,
    buffer = buffer,
  }, self)
end

function Range.from_visual_selection()
  local buffer = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start = Point:from_1_based(start_pos[2], start_pos[3])
  local end_ = Point:from_1_based(end_pos[2], end_pos[3])

  --- visual line mode will select the end point for each row to be int max
  --- which will cause marks to fail. so we have to correct it to the literal
  --- row length
  local end_row, _ = end_:to_vim()
  local end_line =
    vim.api.nvim_buf_get_lines(buffer, end_row, end_row + 1, false)

  --- @type number
  local end_col

  --- another bug where mark >' is beyond the editor.
  --- therefore will just grab from start to end and use the last captured row
  --- as the means to discover the proper end col and end row
  if #end_line == 0 then
    local start_r, _ = start:to_vim()
    local selected_lines =
      vim.api.nvim_buf_get_lines(buffer, start_r, end_row, false)
    end_row = start_r + #selected_lines
    --- another edge case, the buffer may be empty...
    --- sentry literally caught this one
    if #selected_lines == 0 then
      --- an edge to the edge case. we are in 1 based indexing... f
      end_col = 1
    else
      end_col = #selected_lines[#selected_lines]
    end
    --- here is confusing part, we are now in 1 based values
    --- in the geo_spec test, this would result in end_row = 2, end_col = 8
    --- so, there is this -1 because we are going to go from 1 based to 0 based
    end_row = end_row - 1

    --- we need to capture the whole line, therefore its end of line + 1
    end_col = end_col
  else
    --- we are using zero based point, which means length of line includes the new_line character
    end_col = #end_line[1]
  end

  local actual_end = Point.from_0_based(end_row, end_col)
  return Range:new(buffer, start, actual_end)
end

---@param node _99.treesitter.Node
---@param buffer number
---@return _99.Range
function Range:from_ts_node(node, buffer)
  -- ts is zero based
  local start_row, start_col, _ = node:start()
  local end_row, end_col, _ = node:end_()
  local range = {
    start = Point:from_ts_point(start_row, start_col),
    end_ = Point:from_ts_point(end_row, end_col),
    buffer = buffer,
  }

  return setmetatable(range, self)
end

---@param start _99.Mark
---@param end_ _99.Mark
---@return _99.Range
function Range.from_marks(start, end_)
  local start_point = Point.from_mark(start)
  local end_point = Point.from_mark(end_)
  return Range:new(start.buffer, start_point, end_point)
end

--- @param replace_with string[]
function Range:replace_text(replace_with)
  local s_row, s_col = self.start:to_vim()
  local e_row, e_col = self.end_:to_vim()
  vim.api.nvim_buf_set_text(
    self.buffer,
    s_row,
    s_col,
    e_row,
    e_col,
    replace_with
  )
end

--- @param point _99.Point
--- @return boolean
function Range:contains(point)
  local start = project(self.start)
  local stop = project(self.end_)
  local p = project(point)
  return start <= p and p <= stop
end

--- @return string
function Range:to_text()
  local sr, sc = self.start:to_vim()
  local er, ec = self.end_:to_vim()

  --- blank line vis selection
  if sr == er and sc == ec then
    ec = ec + 1
  end

  local text = vim.api.nvim_buf_get_text(self.buffer, sr, sc, er, ec, {})
  return table.concat(text, "\n")
end

--- @param range _99.Range
--- @return boolean
function Range:contains_range(range)
  return self.start:lte(range.start) and self.end_:gte(range.end_)
end

function Range:area()
  local start = project(self.start)
  local end_ = project(self.end_)
  return end_ - start
end

function Range:to_string()
  return string.format(
    "range(%s,%s)",
    self.start:to_string(),
    self.end_:to_string()
  )
end

--- @return _99.Range
function Range.zero()
  return Range:new(0, Point.zero(), Point.zero())
end

return {
  Point = Point,
  Range = Range,
}
