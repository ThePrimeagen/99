local Files = require("99.extensions.files")

--- @class _99.Extensions.Source
--- @field init_for_buffer fun(_99: _99.State): nil
--- @field init fun(_99: _99.State): nil
--- @field refresh_state fun(_99: _99.State): nil

--- @param completion _99.Completion | nil
--- @return _99.Extensions.Source | nil
local function get_source(completion)
  if not completion or not completion.source then
    return
  end
  local source = completion.source
  if source == "cmp" then
    local ok, cmp = pcall(require, "99.extensions.cmp")
    if not ok then
      vim.notify(
        '[99] nvim-cmp is not installed. Install hrsh7th/nvim-cmp or use source = "blink"',
        vim.log.levels.WARN
      )
      return
    end
    return cmp
  end
  if source == "blink" then
    local ok, _ = pcall(require, "blink.compat")
    if not ok then
      vim.notify(
        "[99] blink.compat is required for blink source. Install: { 'saghen/blink.compat', version = '2.*' }",
        vim.log.levels.ERROR
      )
      return
    end
    local cmp_ok, cmp = pcall(require, "99.extensions.cmp")
    if not cmp_ok then
      vim.notify(
        "[99] 99 completion module failed to load",
        vim.log.levels.ERROR
      )
      return
    end
    return cmp
  end
end

return {
  --- @param _99 _99.State
  init = function(_99)
    local source = get_source(_99.completion)
    if not source then
      return
    end
    source.init(_99)
  end,

  capture_project_root = function()
    local cwd = vim.fn.getcwd()
    local git_root = vim.fs.root(cwd, ".git")
    Files.set_project_root(git_root or cwd)
  end,

  --- @param _99 _99.State
  setup_buffer = function(_99)
    local source = get_source(_99.completion)
    if not source then
      return
    end
    source.init_for_buffer(_99)
  end,

  --- @param _99 _99.State
  refresh = function(_99)
    local source = get_source(_99.completion)
    if not source then
      return
    end
    source.refresh_state(_99)
  end,
}
