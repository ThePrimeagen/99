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

Window.capture_input({
  cb = function(_, _)
    print("results")
  end,
  on_load = function()
    print("on_load")
    require("99.extensions").setup_buffer(require("99").__get_state())
  end,
  rules = _99.__get_state().rules,
})
