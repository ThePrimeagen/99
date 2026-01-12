-- luacheck: globals describe it assert after_each
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same
local Levels = require("99.logger.level")

--- @param content string[]
--- @param row number
--- @param col number
--- @return _99.test.Provider, number
local function setup(content, row, col)
    local p = test_utils.TestProvider.new()
    _99.setup({
        provider = p,
        logger = {
            error_cache_level = Levels.ERROR,
            type = "print",
        },
    })

    local buffer = test_utils.create_file(content, "ruby", row, col)
    return p, buffer
end

--- @param buffer number
--- @return string[]
local function r(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("Ruby Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic methods", function()
        it("detects and fills a simple method", function()
            local content = {
                "def greet(name)",
                "end",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def greet(name)"
            )

            p:resolve("success", 'def greet(name)\n  "Hello, #{name}!"\nend')
            test_utils.next_frame()

            eq({
                "def greet(name)",
                '  "Hello, #{name}!"',
                "end",
            }, r(buffer))
        end)

        it("detects method with default parameters", function()
            local content = {
                "def greet(name = 'World')",
                "end",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def greet(name = 'World')"
            )

            p:resolve(
                "success",
                "def greet(name = 'World')\n  puts \"Hello, #{name}!\"\nend"
            )
            test_utils.next_frame()

            eq({
                "def greet(name = 'World')",
                '  puts "Hello, #{name}!"',
                "end",
            }, r(buffer))
        end)

        it("detects method with keyword arguments", function()
            local content = {
                "def create_user(name:, email:, age: nil)",
                "end",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def create_user(name:, email:, age: nil)"
            )
        end)
    end)

    describe("comments", function()
        it("includes preceding comment in context", function()
            local content = {
                "# Greets the user by name",
                "def greet(name)",
                "end",
            }
            local p, _ = setup(content, 2, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "# Greets the user by name"
            )
        end)

        it("includes multi-line comments", function()
            local content = {
                "# Process the input data",
                "# and return the result",
                "def process(data)",
                "end",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "# Process the input data"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "# and return the result"
            )
        end)
    end)

    describe("class methods", function()
        it("includes enclosing class in context", function()
            local content = {
                "class Calculator",
                "  def initialize",
                "    @value = 0",
                "  end",
                "",
                "  def add(n)",
                "  end",
                "end",
            }
            local p, buffer = setup(content, 6, 2)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "class Calculator"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def add(n)"
            )

            p:resolve("success", "def add(n)\n    @value += n\n  end")
            test_utils.next_frame()

            eq({
                "class Calculator",
                "  def initialize",
                "    @value = 0",
                "  end",
                "",
                "  def add(n)",
                "    @value += n",
                "  end",
                "end",
            }, r(buffer))
        end)

        it("handles self. class method", function()
            local content = {
                "class Math",
                "  def self.square(x)",
                "  end",
                "end",
            }
            local p, _ = setup(content, 2, 2)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "class Math"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def self.square(x)"
            )
        end)
    end)

    describe("modules", function()
        it("includes enclosing module in context", function()
            local content = {
                "module Helpers",
                "  def format_name(name)",
                "  end",
                "end",
            }
            local p, _ = setup(content, 2, 2)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "module Helpers"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def format_name(name)"
            )
        end)

        it("handles nested module and class", function()
            local content = {
                "module Services",
                "  class UserService",
                "    def create(params)",
                "    end",
                "  end",
                "end",
            }
            local p, _ = setup(content, 3, 4)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "class UserService"
            )
        end)
    end)

    describe("blocks", function()
        it("detects do-end block as fillable", function()
            local content = {
                "items.each do |item|",
                "end",
            }
            -- Cursor at col 12 (inside the do_block, after "items.each ")
            local p, buffer = setup(content, 1, 12)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "do |item|"
            )

            p:resolve("success", "do |item|\n  puts item\nend")
            test_utils.next_frame()

            eq({
                "items.each do |item|",
                "  puts item",
                "end",
            }, r(buffer))
        end)

        it("detects brace block as fillable", function()
            local content = {
                "items.map { |x| x }",
            }
            local p, buffer = setup(content, 1, 12)

            _99.fill_in_function()

            assert.is_not_nil(p.request)

            p:resolve("success", "{ |x| x * 2 }")
            test_utils.next_frame()

            eq({
                "items.map { |x| x * 2 }",
            }, r(buffer))
        end)
    end)

    describe("edge cases", function()
        it("handles empty method body", function()
            local content = {
                "def empty_method",
                "end",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)

            p:resolve(
                "success",
                "def empty_method\n  # Implementation\n  true\nend"
            )
            test_utils.next_frame()

            eq({
                "def empty_method",
                "  # Implementation",
                "  true",
                "end",
            }, r(buffer))
        end)

        it("cancels request when stop_all_requests is called", function()
            local content = {
                "def cancel_me",
                "end",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            assert.is_false(p.request.request:is_cancelled())

            _99.stop_all_requests()
            test_utils.next_frame()

            assert.is_true(p.request.request:is_cancelled())

            p:resolve("success", "def cancel_me\n  'should not appear'\nend")
            test_utils.next_frame()

            eq(content, r(buffer))
        end)

        it("handles error response gracefully", function()
            local content = {
                "def error_case",
                "end",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            p:resolve("failed", "API error occurred")
            test_utils.next_frame()

            eq(content, r(buffer))
        end)
    end)
end)
