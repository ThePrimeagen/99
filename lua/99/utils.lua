local M = {}
--- TODO: some people change their current working directory as they open new
--- directories.  if this is still the case in neovim land, then we will need
--- to make the _99_state have the project directory.
--- @return string
function M.random_file()
    local tmp_dir = "/tmp/99"
    if vim.fn.isdirectory(tmp_dir) == 0 then
        vim.fn.mkdir(tmp_dir, "p")
    end
    return string.format(
        "%s/%d",
        tmp_dir,
        math.floor(math.random() * 1000000)
    )
end

return M
