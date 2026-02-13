local M = {}
--- TODO: some people change their current working directory as they open new
--- directories.  if this is still the case in neovim land, then we will need
--- to make the _99_state have the project directory.
--- @return string
function M.random_file(dir)
  local directory = dir or (vim.uv.cwd() .. "/tmp")
  return string.format("%s/99-%d", directory, math.floor(math.random() * 10000))
end

return M
