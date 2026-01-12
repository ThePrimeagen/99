-- luacheck: globals describe it assert after_each
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

local function setup(content, row, col)
    return test_utils.setup_test(content, "ruby", row, col)
end
local r = test_utils.lines

describe("Ruby Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic methods", function()
        it("detects method with default parameters", function()
            local content = { "def greet(name = 'World')", "end" }
            local p, buffer = setup(content, 1, 0)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
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
            local content =
                { "def create_user(name:, email:, age: nil)", "end" }
            local p, _ = setup(content, 1, 0)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "def create_user(name:, email:, age: nil)"
            )
        end)
    end)

    describe("class methods", function()
        it("handles self. class method", function()
            local content =
                { "class Math", "  def self.square(x)", "  end", "end" }
            local p, _ = setup(content, 2, 2)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "EnclosingContext",
                "class Math"
            )
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "def self.square(x)"
            )
        end)
    end)

    describe("modules", function()
        it("includes enclosing module in context", function()
            local content =
                { "module Helpers", "  def format_name(name)", "  end", "end" }
            local p, _ = setup(content, 2, 2)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "EnclosingContext",
                "module Helpers"
            )
            test_utils.assert_section_contains(
                p.request.query,
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
            test_utils.assert_section_contains(
                p.request.query,
                "EnclosingContext",
                "class UserService"
            )
        end)
    end)

    describe("blocks", function()
        it("detects do-end block as fillable", function()
            local content = { "items.each do |item|", "end" }
            local p, buffer = setup(content, 1, 12)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "do |item|"
            )

            p:resolve("success", "do |item|\n  puts item\nend")
            test_utils.next_frame()
            eq({ "items.each do |item|", "  puts item", "end" }, r(buffer))
        end)

        it("detects brace block as fillable", function()
            local content = { "items.map { |x| x }" }
            local p, buffer = setup(content, 1, 12)
            _99.fill_in_function()
            assert.is_not_nil(p.request)

            p:resolve("success", "{ |x| x * 2 }")
            test_utils.next_frame()
            eq({ "items.map { |x| x * 2 }" }, r(buffer))
        end)
    end)
end)
