local M = {}

--- Normalize absolute paths to handle symlinks (e.g., /tmp -> /private/tmp on macOS).
--- Relative paths are preserved as-is.
--- @param filepath string
--- @return string normalized path
local function normalize_path(filepath)
  -- Only normalize absolute paths
  if not filepath:match("^/") then
    return filepath
  end

  -- Extract parent directory and basename
  local parent = filepath:match("^(.+)/[^/]+$")
  local basename = filepath:match("[^/]+$")

  if not parent or not basename then
    return filepath
  end

  -- Get realpath of parent directory
  local ok, real_parent = pcall(vim.fn.resolve, parent)
  if not ok or not real_parent or real_parent == "" then
    return filepath
  end

  -- If parent resolved differently, reconstruct path
  if real_parent ~= parent then
    return real_parent .. "/" .. basename
  end

  return filepath
end

--- @return _99.Search.Result | nil
function M.parse_line(line)
  local filepath, lnum_raw, rest = line:match("^(.-):([^:]+):(.+)$")
  if not filepath or not lnum_raw or not rest then
    return nil
  end

  local col_raw, _, notes = rest:match("^([^,]+),([^,]+),?(.*)$")
  if not col_raw then
    return nil
  end

  local lnum = tonumber(lnum_raw) or 1
  local col = tonumber(col_raw) or 1

  return {
    filename = normalize_path(filepath),
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
