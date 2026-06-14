local M = {}

--- @return _99.Search.Result | nil
function M.parse_line(line)
  local filepath, lnum_raw, col_raw, _, notes = line:match("^(.-):(%d+):(%d+),([^,]+),?(.*)$")
  if not filepath or not lnum_raw or not col_raw then
    return nil
  end

  local lnum = tonumber(lnum_raw) or 1
  local col = tonumber(col_raw) or 1

  return {
    filename = filepath,
    lnum = lnum,
    col = col,
    text = notes or "",
  }
end

--- @param response string
--- @return _99.Search.Result[]
function M.create_qfix_entries(response)
  local lines = vim.split(response, "\n")
  local qf_list = {} --[[ @as _99.Search.Result[] ]]

  for _, line in ipairs(lines) do
    local res = M.parse_line(line)
    if res then
      table.insert(qf_list, res)
    end
  end
  return qf_list
end

return M