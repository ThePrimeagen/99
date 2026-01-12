-- luacheck: globals describe it assert after_each
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

local function setup(content, row, col)
    return test_utils.setup_test(content, "python", row, col)
end
local r = test_utils.lines

describe("Python Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects function with type hints", function()
            local content = { "def add(a: int, b: int) -> int:", "    pass" }
            local p, buffer = setup(content, 1, 0)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "def add(a: int, b: int) -> int:"
            )

            p:resolve(
                "success",
                "def add(a: int, b: int) -> int:\n    return a + b"
            )
            test_utils.next_frame()
            eq(
                { "def add(a: int, b: int) -> int:", "    return a + b" },
                r(buffer)
            )
        end)
    end)

    describe("comments and docstrings", function()
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
            local pattern =
                "<FunctionDocumentation>.-# This comment is too far.-</FunctionDocumentation>"
            assert.is_nil(p.request.query:match(pattern))
        end)
    end)

    describe("class methods", function()
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
            test_utils.assert_section_exists(
                p.request.query,
                "EnclosingContext"
            )
            test_utils.assert_section_contains(
                p.request.query,
                "EnclosingContext",
                "@staticmethod"
            )
            test_utils.assert_section_contains(
                p.request.query,
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
            test_utils.assert_section_exists(
                p.request.query,
                "EnclosingContext"
            )
            test_utils.assert_section_contains(
                p.request.query,
                "EnclosingContext",
                "@classmethod"
            )
        end)
    end)

    describe("lambda expressions", function()
        it("detects lambda in assignment", function()
            local content = { "double = lambda x: x" }
            local p, buffer = setup(content, 1, 10)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "lambda x:"
            )

            p:resolve("success", "lambda x: x * 2")
            test_utils.next_frame()
            eq({ "double = lambda x: x * 2" }, r(buffer))
        end)
    end)

    describe("edge cases", function()
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
            test_utils.assert_section_contains(
                p.request.query,
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
    end)
end)
