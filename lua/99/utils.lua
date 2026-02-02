local path_separator = package.config:sub(1, 1)

local M = {}

--- Formats a path to work on all operating systems
--- @param ... string Path components to join
--- @return string
local function format_path(...)
  local parts = { ... }
  return table.concat(parts, path_separator)
end

--- TODO: some people change their current working directory as they open new
--- directories.  if this is still the case in neovim land, then we will need
--- to make the _99_state have the project directory.
--- @return string
function M.random_file()
  return string.format(
    format_path("%s", "tmp", "99-%d"),
    vim.uv.cwd(),
    math.floor(math.random() * 10000)
  )
end

return M
