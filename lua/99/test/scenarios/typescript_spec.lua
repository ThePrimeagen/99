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

    local buffer = test_utils.create_file(content, "typescript", row, col)
    return p, buffer
end

--- @param buffer number
--- @return string[]
local function r(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("TypeScript Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects and fills a named function", function()
            local content = {
                "function greet(name: string): string {",
                "}",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "function greet(name: string): string {"
            )

            p:resolve(
                "success",
                "function greet(name: string): string {\n    return `Hello, ${name}!`;\n}"
            )
            test_utils.next_frame()

            eq({
                "function greet(name: string): string {",
                "    return `Hello, ${name}!`;",
                "}",
            }, r(buffer))
        end)

        it("detects anonymous function assigned to const", function()
            local content = {
                "",
                "const foo = function() {}",
            }
            local p, buffer = setup(content, 2, 12)

            _99.fill_in_function()

            assert.is_not_nil(p.request)

            p:resolve("success", "function() {\n    return 42;\n}")
            test_utils.next_frame()

            eq({
                "",
                "const foo = function() {",
                "    return 42;",
                "}",
            }, r(buffer))
        end)

        it("detects arrow function", function()
            local content = {
                "const add = (a: number, b: number): number => {",
                "};",
            }
            local p, buffer = setup(content, 1, 12)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
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

        it("detects async function", function()
            local content = {
                "async function fetchData(url: string): Promise<string> {",
                "}",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "async function fetchData(url: string)"
            )
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
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "/** Greets the user by name */"
            )
        end)

        it("includes preceding single-line comment", function()
            local content = {
                "// Process the input data",
                "function process(data: Buffer): void {",
                "}",
            }
            local p, _ = setup(content, 2, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "// Process the input data"
            )
        end)
    end)

    describe("class methods", function()
        it("includes enclosing class in context", function()
            local content = {
                "class Calculator {",
                "    private value: number = 0;",
                "",
                "    add(n: number): void {",
                "    }",
                "}",
            }
            local p, buffer = setup(content, 4, 4)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_exists(query, "EnclosingContext")
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "add(n: number): void {"
            )

            p:resolve(
                "success",
                "add(n: number): void {\n        this.value += n;\n    }"
            )
            test_utils.next_frame()

            eq({
                "class Calculator {",
                "    private value: number = 0;",
                "",
                "    add(n: number): void {",
                "        this.value += n;",
                "    }",
                "}",
            }, r(buffer))
        end)

        it("detects static method with class context", function()
            local content = {
                "class Math {",
                "    static square(x: number): number {",
                "    }",
                "}",
            }
            local p, _ = setup(content, 2, 4)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_exists(query, "EnclosingContext")
            test_utils.assert_section_contains(
                query,
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
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
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
            local query = p.request.query
            -- Should have enclosing class context
            test_utils.assert_section_exists(query, "EnclosingContext")
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "greet(name: string): string {"
            )
        end)
    end)

    describe("edge cases", function()
        it("cancels request when stop_all_requests is called", function()
            local content = {
                "function cancelMe(): void {",
                "}",
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
                "function cancelMe(): void {\n    console.log('should not appear');\n}"
            )
            test_utils.next_frame()

            eq(content, r(buffer))
        end)

        it("handles error response gracefully", function()
            local content = {
                "function errorCase(): void {",
                "}",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            p:resolve("failed", "API error occurred")
            test_utils.next_frame()

            eq(content, r(buffer))
        end)
    end)
end)
