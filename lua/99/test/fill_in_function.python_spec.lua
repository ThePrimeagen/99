---@module "plenary.busted"

-- luacheck: globals describe it assert
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local Levels = require("99.logger.level")
local eq = assert.are.same

--- @param content string[]
--- @param row number
--- @param col number
--- @param lang string?
--- @return _99.test.Provider, number
local function setup(content, row, col, lang)
  assert(lang, "lang must be provided")
  local provider = test_utils.TestProvider.new()
  _99.setup({
    provider = provider,
    logger = {
      error_cache_level = Levels.ERROR,
      type = "print",
    },
  })

  local buffer = test_utils.create_file(content, lang, row, col)
  return provider, buffer
end

--- @param buffer number
--- @return string[]
local function read(buffer)
  return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("fill_in_function", function()
  it("fill in python function", function()
    local python_content = {
      "",
      "def test():",
      "    pass",
    }
    local provider, buffer = setup(python_content, 2, 5, "python")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(python_content, read(buffer))

    provider:resolve("success", "def test():\n    return 42")
    test_utils.next_frame()

    local expected_state = {
      "",
      "def test():",
      "    return 42",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)

  it("fill in python function with docstring", function()
    local python_content = {
      "",
      "def calculate(x, y):",
      '    """Calculate the sum of x and y."""',
      "    # TODO: implement",
      "    pass",
    }
    local provider, buffer = setup(python_content, 2, 5, "python")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(python_content, read(buffer))

    provider:resolve(
      "success",
      'def calculate(x, y):\n    """Calculate the sum of x and y."""\n    return x + y'
    )
    test_utils.next_frame()

    local expected_state = {
      "",
      "def calculate(x, y):",
      '    """Calculate the sum of x and y."""',
      "    return x + y",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)

  it("fill in python method with self parameter", function()
    local python_content = {
      "",
      "class Calculator:",
      "    def add(self, a, b):",
      "        pass",
    }
    local provider, buffer = setup(python_content, 3, 10, "python")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(python_content, read(buffer))

    provider:resolve("success", "def add(self, a, b):\n        return a + b")
    test_utils.next_frame()

    local expected_state = {
      "",
      "class Calculator:",
      "    def add(self, a, b):",
      "        return a + b",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)
end)
