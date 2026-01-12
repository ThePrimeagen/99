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

    local buffer = test_utils.create_file(content, "python", row, col)
    return p, buffer
end

--- @param buffer number
--- @return string[]
local function r(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("Python Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects and fills a simple function", function()
            local content = {
                "def greet(name):",
                "    pass",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def greet(name):"
            )

            p:resolve(
                "success",
                'def greet(name):\n    return f"Hello, {name}!"'
            )
            test_utils.next_frame()

            eq({
                "def greet(name):",
                '    return f"Hello, {name}!"',
            }, r(buffer))
        end)

        it("detects function with type hints", function()
            local content = {
                "def add(a: int, b: int) -> int:",
                "    pass",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def add(a: int, b: int) -> int:"
            )

            p:resolve(
                "success",
                "def add(a: int, b: int) -> int:\n    return a + b"
            )
            test_utils.next_frame()

            eq({
                "def add(a: int, b: int) -> int:",
                "    return a + b",
            }, r(buffer))
        end)

        it("detects async function", function()
            local content = {
                "async def fetch_data(url):",
                "    pass",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "async def fetch_data(url):"
            )

            p:resolve(
                "success",
                "async def fetch_data(url):\n    return await http.get(url)"
            )
            test_utils.next_frame()

            eq({
                "async def fetch_data(url):",
                "    return await http.get(url)",
            }, r(buffer))
        end)
    end)

    describe("comments and docstrings", function()
        it("includes preceding comment in context", function()
            local content = {
                "# This function greets a user",
                "def greet(name):",
                "    pass",
            }
            local p, _ = setup(content, 2, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "# This function greets a user"
            )
        end)

        it("includes multi-line comments", function()
            local content = {
                "# First line of documentation",
                "# Second line of documentation",
                "def process(data):",
                "    pass",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "# First line of documentation"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "# Second line of documentation"
            )
        end)

        it("does not include comments too far from function", function()
            local content = {
                "# This comment is too far",
                "",
                "",
                "",
                "def greet(name):",
                "    pass",
            }
            local p, _ = setup(content, 5, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            -- Comment is more than 2 lines away, should not be included
            assert.is_nil(
                query:match(
                    "<FunctionDocumentation>.-# This comment is too far.-</FunctionDocumentation>"
                )
            )
        end)
    end)

    describe("class methods", function()
        it("includes enclosing class in context", function()
            local content = {
                "class Calculator:",
                "    def __init__(self):",
                "        self.value = 0",
                "",
                "    def add(self, n):",
                "        pass",
            }
            local p, buffer = setup(content, 5, 4)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "class Calculator:"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def add(self, n):"
            )

            p:resolve("success", "def add(self, n):\n        self.value += n")
            test_utils.next_frame()

            eq({
                "class Calculator:",
                "    def __init__(self):",
                "        self.value = 0",
                "",
                "    def add(self, n):",
                "        self.value += n",
            }, r(buffer))
        end)

        it("handles staticmethod decorator", function()
            local content = {
                "class Math:",
                "    @staticmethod",
                "    def square(x):",
                "        pass",
            }
            local p, _ = setup(content, 3, 4)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            -- The class context includes the class body (containing the decorated method)
            test_utils.assert_section_exists(query, "EnclosingContext")
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "@staticmethod"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def square(x):"
            )
        end)

        it("handles classmethod decorator", function()
            local content = {
                "class Counter:",
                "    count = 0",
                "",
                "    @classmethod",
                "    def increment(cls):",
                "        pass",
            }
            local p, _ = setup(content, 5, 4)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            -- The class context includes the class body
            test_utils.assert_section_exists(query, "EnclosingContext")
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "@classmethod"
            )
        end)
    end)

    describe("lambda expressions", function()
        it("detects lambda in assignment", function()
            local content = {
                "double = lambda x: x",
            }
            local p, buffer = setup(content, 1, 10)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "lambda x:"
            )

            p:resolve("success", "lambda x: x * 2")
            test_utils.next_frame()

            eq({
                "double = lambda x: x * 2",
            }, r(buffer))
        end)
    end)

    describe("edge cases", function()
        it("handles function with no body (just pass)", function()
            local content = {
                "def placeholder():",
                "    pass",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)

            p:resolve(
                "success",
                "def placeholder():\n    print('Implemented!')"
            )
            test_utils.next_frame()

            eq({
                "def placeholder():",
                "    print('Implemented!')",
            }, r(buffer))
        end)

        it("handles nested function", function()
            local content = {
                "def outer():",
                "    def inner():",
                "        pass",
                "    return inner",
            }
            local p, buffer = setup(content, 2, 4)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "def inner():"
            )

            p:resolve("success", "def inner():\n        return 42")
            test_utils.next_frame()

            eq({
                "def outer():",
                "    def inner():",
                "        return 42",
                "    return inner",
            }, r(buffer))
        end)

        it("cancels request when stop_all_requests is called", function()
            local content = {
                "def cancel_me():",
                "    pass",
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
                "def cancel_me():\n    return 'should not appear'"
            )
            test_utils.next_frame()

            -- Buffer should remain unchanged
            eq(content, r(buffer))
        end)

        it("handles error response gracefully", function()
            local content = {
                "def error_case():",
                "    pass",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            p:resolve("failed", "API error occurred")
            test_utils.next_frame()

            -- Buffer should remain unchanged
            eq(content, r(buffer))
        end)
    end)
end)
