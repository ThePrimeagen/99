---@diagnostic disable-next-line: undefined-global
R("99")
local _99 = require("99")
local Window = require("99.window")
_99.setup({
  completion = {
    custom_rules = {
      "~/personal/skills/skills",
    },
    source = "cmp",
  },
})

print(vim.inspect(Agents.rules(_99.__get_state())))
print(vim.inspect(Helpers.ls("/home/theprimeagen/.behaviors")))

--- @class Config
--- @field width number
--- @field height number
--- @field offset_row number
--- @field offset_col number
--- @field border string
function create_window(config)
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Configure the floating window
  local win_config = {
    relative = "editor",
    width = config.width,
    height = config.height,
    row = config.offset_row,
    col = config.offset_col,
    style = "minimal",
    border = "rounded",
  }

  -- Open the floating window
  local win = vim.api.nvim_open_win(buf, true, win_config)

  return { buf = buf, win = win }
end
