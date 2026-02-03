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
  it("fill in javascript function declaration", function()
    local content = {
      "",
      "function fibonacci(n) {",
      "}",
    }
    local provider, buffer = setup(content, 2, 5, "javascript")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(content, read(buffer))

    provider:resolve(
      "success",
      "function fibonacci(n) {\n  if (n <= 1) return n;\n  return fibonacci(n - 1) + fibonacci(n - 2);\n}"
    )
    test_utils.next_frame()

    local expected_state = {
      "",
      "function fibonacci(n) {",
      "  if (n <= 1) return n;",
      "  return fibonacci(n - 1) + fibonacci(n - 2);",
      "}",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)

  it("fill in javascript arrow function", function()
    local content = {
      "",
      "const add = (a, b) => {",
      "}",
    }
    local provider, buffer = setup(content, 2, 15, "javascript")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(content, read(buffer))

    provider:resolve("success", "(a, b) => {\n  return a + b;\n}")
    test_utils.next_frame()

    local expected_state = {
      "",
      "const add = (a, b) => {",
      "  return a + b;",
      "}",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)
end)
