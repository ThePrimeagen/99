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
  it("fill in rust function", function()
    local content = {
      "",
      "fn fibonacci(n: u32) -> u32 {",
      "}",
    }
    local provider, buffer = setup(content, 2, 5, "rust")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(content, read(buffer))

    local response = "fn fibonacci(n: u32) -> u32 {\n"
      .. "    if n <= 1 {\n"
      .. "        return n;\n"
      .. "    }\n"
      .. "    fibonacci(n - 1) + fibonacci(n - 2)\n"
      .. "}"
    provider:resolve("success", response)
    test_utils.next_frame()

    local expected_state = {
      "",
      "fn fibonacci(n: u32) -> u32 {",
      "    if n <= 1 {",
      "        return n;",
      "    }",
      "    fibonacci(n - 1) + fibonacci(n - 2)",
      "}",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)

  it("fill in rust impl method", function()
    local content = {
      "",
      "impl Calculator {",
      "    fn add(&self, a: i32, b: i32) -> i32 {",
      "    }",
      "}",
    }
    local provider, buffer = setup(content, 3, 10, "rust")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(content, read(buffer))

    provider:resolve(
      "success",
      "fn add(&self, a: i32, b: i32) -> i32 {\n        a + b\n    }"
    )
    test_utils.next_frame()

    local expected_state = {
      "",
      "impl Calculator {",
      "    fn add(&self, a: i32, b: i32) -> i32 {",
      "        a + b",
      "    }",
      "}",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)
end)
