-- luacheck: globals describe it assert after_each
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

local function setup(content, row, col)
    return test_utils.setup_test(content, "typescript", row, col)
end
local r = test_utils.lines

describe("TypeScript Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects anonymous function assigned to const", function()
            local content = { "", "const foo = function() {}" }
            local p, buffer = setup(content, 2, 12)
            _99.fill_in_function()
            assert.is_not_nil(p.request)

            p:resolve("success", "function() {\n    return 42;\n}")
            test_utils.next_frame()
            eq(
                { "", "const foo = function() {", "    return 42;", "}" },
                r(buffer)
            )
        end)

        it("detects arrow function", function()
            local content =
                { "const add = (a: number, b: number): number => {", "};" }
            local p, buffer = setup(content, 1, 12)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "(a: number, b: number): number =>"
            )

            p:resolve(
                "success",
                "(a: number, b: number): number => {\n    return a + b;\n}"
            )
            test_utils.next_frame()
            eq({
                "const add = (a: number, b: number): number => {",
                "    return a + b;",
                "};",
            }, r(buffer))
        end)
    end)

    describe("comments", function()
        it("includes preceding JSDoc comment", function()
            local content = {
                "/** Greets the user by name */",
                "function greet(name: string): string {",
                "}",
            }
            local p, _ = setup(content, 2, 0)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionDocumentation",
                "/** Greets the user by name */"
            )
        end)
    end)

    describe("class methods", function()
        it("detects static method", function()
            local content = {
                "class Math {",
                "    static square(x: number): number {",
                "    }",
                "}",
            }
            local p, _ = setup(content, 2, 4)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_exists(
                p.request.query,
                "EnclosingContext"
            )
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "static square(x: number): number {"
            )
        end)

        it("detects private method", function()
            local content = {
                "class Service {",
                "    private helper(): void {",
                "    }",
                "}",
            }
            local p, _ = setup(content, 2, 4)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "private helper(): void {"
            )
        end)
    end)

    describe("interfaces", function()
        it("detects function in class implementing interface", function()
            local content = {
                "interface Greeter {",
                "    greet(name: string): string;",
                "}",
                "",
                "class HelloGreeter implements Greeter {",
                "    greet(name: string): string {",
                "    }",
                "}",
            }
            local p, _ = setup(content, 6, 4)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_exists(
                p.request.query,
                "EnclosingContext"
            )
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "greet(name: string): string {"
            )
        end)
    end)
end)
