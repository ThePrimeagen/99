-- luacheck: globals describe it assert before_each after_each
local _99 = require("99")
local Window = require("99.window")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

describe("state", function()
  local provider
  local previous_list_uis

  before_each(function()
    provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    previous_list_uis = vim.api.nvim_list_uis
    vim.api.nvim_list_uis = function()
      return {
        { width = 120, height = 40 },
      }
    end
  end)

  after_each(function()
    Window.clear_active_popups()
    vim.cmd("silent! cclose")
    vim.api.nvim_list_uis = previous_list_uis
  end)

  it("is active when capture input window is open", function()
    local state = _99.__get_state()
    eq(false, state:active())

    Window.capture_input("Prompt", {
      cb = function() end,
      keymap = {
        [":w"] = "submit",
      },
    })

    eq(true, state:active())
  end)

  it("is active when quickfix window is open", function()
    local state = _99.__get_state()
    local buffer = test_utils.create_file({ "hello" }, "lua", 1, 0)
    eq(false, state:active())

    vim.fn.setqflist({}, "r", {
      title = "99 Results",
      items = {
        {
          bufnr = buffer,
          lnum = 1,
          col = 1,
          text = "note",
        },
      },
    })
    vim.cmd("copen")

    eq(true, state:active())
  end)
end)
