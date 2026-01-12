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

    local buffer = test_utils.create_file(content, "lua", row, col)
    return p, buffer
end

--- @param buffer number
--- @return string[]
local function r(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("Lua Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects and fills a named function", function()
            local content = {
                "function greet(name)",
                "end",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "function greet(name)"
            )

            p:resolve(
                "success",
                'function greet(name)\n    return "Hello, " .. name\nend'
            )
            test_utils.next_frame()

            eq({
                "function greet(name)",
                '    return "Hello, " .. name',
                "end",
            }, r(buffer))
        end)

        it("detects local function", function()
            local content = {
                "local function add(a, b)",
                "end",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "local function add(a, b)"
            )
        end)

        it("detects anonymous function assigned to variable", function()
            local content = {
                "",
                "local foo = function() end",
            }
            local p, buffer = setup(content, 2, 12)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "function() end"
            )

            p:resolve("success", "function()\n    return 42\nend")
            test_utils.next_frame()

            eq({
                "",
                "local foo = function()",
                "    return 42",
                "end",
            }, r(buffer))
        end)
    end)

    describe("comments", function()
        it("includes preceding comment in context", function()
            local content = {
                "-- Greets the user by name",
                "function greet(name)",
                "end",
            }
            local p, _ = setup(content, 2, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "-- Greets the user by name"
            )
        end)

        it("includes multi-line comments", function()
            local content = {
                "-- Process the input",
                "-- and return result",
                "function process(data)",
                "end",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "-- Process the input"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "-- and return result"
            )
        end)
    end)

    describe("method syntax", function()
        it("detects method with colon syntax", function()
            local content = {
                "local M = {}",
                "",
                "function M:greet(name)",
                "end",
                "",
                "return M",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "function M:greet(name)"
            )
        end)

        it("detects method with dot syntax", function()
            local content = {
                "local M = {}",
                "",
                "function M.add(self, n)",
                "end",
                "",
                "return M",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "function M.add(self, n)"
            )
        end)
    end)

    describe("edge cases", function()
        it("cancels request when stop_all_requests is called", function()
            local content = {
                "function cancel_me()",
                "end",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            assert.is_false(p.request.request:is_cancelled())

            _99.stop_all_requests()
            test_utils.next_frame()

            assert.is_true(p.request.request:is_cancelled())

            p:resolve(
                "success",
                "function cancel_me()\n    return 'should not appear'\nend"
            )
            test_utils.next_frame()

            eq(content, r(buffer))
        end)

        it("handles error response gracefully", function()
            local content = {
                "function error_case()",
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
