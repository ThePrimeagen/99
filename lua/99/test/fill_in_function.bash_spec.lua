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
  it("fill in bash function", function()
    local content = {
      "",
      "fibonacci() {",
      "}",
    }
    local provider, buffer = setup(content, 2, 5, "bash")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(content, read(buffer))

    local response = "fibonacci() {\n"
      .. "    local n=$1\n"
      .. '    if [ "$n" -le 1 ]; then\n'
      .. '        echo "$n"\n'
      .. "        return\n"
      .. "    fi\n"
      .. "    echo $((n))\n"
      .. "}"
    provider:resolve("success", response)
    test_utils.next_frame()

    local expected_state = {
      "",
      "fibonacci() {",
      "    local n=$1",
      '    if [ "$n" -le 1 ]; then',
      '        echo "$n"',
      "        return",
      "    fi",
      "    echo $((n))",
      "}",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)

  it("fill in bash function with function keyword", function()
    local content = {
      "",
      "function greet() {",
      "    # say hello",
      "}",
    }
    local provider, buffer = setup(content, 2, 5, "bash")
    local state = _99.__get_state()

    _99.fill_in_function()

    eq(1, state:active_request_count())
    eq(content, read(buffer))

    provider:resolve("success", 'function greet() {\n    echo "Hello, $1!"\n}')
    test_utils.next_frame()

    local expected_state = {
      "",
      "function greet() {",
      '    echo "Hello, $1!"',
      "}",
    }
    eq(expected_state, read(buffer))
    eq(0, state:active_request_count())
  end)
end)
