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

    local buffer = test_utils.create_file(content, "c", row, col)
    return p, buffer
end

--- @param buffer number
--- @return string[]
local function r(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("C Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects and fills a simple function", function()
            local content = {
                "int add(int a, int b) {",
                "}",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "int add(int a, int b) {"
            )

            p:resolve(
                "success",
                "int add(int a, int b) {\n    return a + b;\n}"
            )
            test_utils.next_frame()

            eq({
                "int add(int a, int b) {",
                "    return a + b;",
                "}",
            }, r(buffer))
        end)

        it("detects void function", function()
            local content = {
                "void print_hello(void) {",
                "}",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "void print_hello(void) {"
            )
        end)

        it("detects static function", function()
            local content = {
                "static int helper(int x) {",
                "}",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "static int helper(int x) {"
            )
        end)

        it("detects function with pointer return type", function()
            local content = {
                "char* get_name(void) {",
                "}",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "char* get_name(void) {"
            )
        end)
    end)

    describe("comments", function()
        it("includes preceding single-line comment", function()
            local content = {
                "// Adds two integers together",
                "int add(int a, int b) {",
                "}",
            }
            local p, _ = setup(content, 2, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "// Adds two integers together"
            )
        end)

        it("includes preceding block comment", function()
            local content = {
                "/* Multiplies two integers */",
                "int multiply(int a, int b) {",
                "}",
            }
            local p, _ = setup(content, 2, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "/* Multiplies two integers */"
            )
        end)

        it("includes multi-line block comment", function()
            local content = {
                "/*",
                " * Process the data",
                " * and return the result",
                " */",
                "int process(int* data, int len) {",
                "}",
            }
            local p, _ = setup(content, 5, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "Process the data"
            )
        end)
    end)

    describe("structs", function()
        it("includes enclosing struct context", function()
            -- Note: C doesn't have methods in structs, but we can test struct context
            -- if a function operates on a struct type
            local content = {
                "struct Point {",
                "    int x;",
                "    int y;",
                "};",
                "",
                "int point_distance(struct Point* p1, struct Point* p2) {",
                "}",
            }
            local p, buffer = setup(content, 6, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "int point_distance(struct Point* p1, struct Point* p2) {"
            )

            p:resolve(
                "success",
                "int point_distance(struct Point* p1, struct Point* p2) {\n"
                    .. "    int dx = p2->x - p1->x;\n"
                    .. "    int dy = p2->y - p1->y;\n"
                    .. "    return dx*dx + dy*dy;\n}"
            )
            test_utils.next_frame()

            eq({
                "struct Point {",
                "    int x;",
                "    int y;",
                "};",
                "",
                "int point_distance(struct Point* p1, struct Point* p2) {",
                "    int dx = p2->x - p1->x;",
                "    int dy = p2->y - p1->y;",
                "    return dx*dx + dy*dy;",
                "}",
            }, r(buffer))
        end)
    end)

    describe("prototypes in buffer", function()
        it("includes prototype from same file", function()
            local content = {
                "int calculate(int x);",
                "",
                "int calculate(int x) {",
                "}",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionPrototypes",
                "int calculate(int x);"
            )
        end)

        it("includes multiple prototypes when available", function()
            local content = {
                "int add(int a, int b);",
                "int subtract(int a, int b);",
                "",
                "int add(int a, int b) {",
                "}",
            }
            local p, _ = setup(content, 4, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionPrototypes",
                "int add(int a, int b);"
            )
        end)
    end)

    describe("edge cases", function()
        it("handles empty function body", function()
            local content = {
                "void empty(void) {",
                "}",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)

            p:resolve(
                "success",
                'void empty(void) {\n    printf("implemented\\n");\n}'
            )
            test_utils.next_frame()

            eq({
                "void empty(void) {",
                '    printf("implemented\\n");',
                "}",
            }, r(buffer))
        end)

        it("cancels request when stop_all_requests is called", function()
            local content = {
                "void cancel_me(void) {",
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
                'void cancel_me(void) {\n    printf("should not appear");\n}'
            )
            test_utils.next_frame()

            eq(content, r(buffer))
        end)

        it("handles error response gracefully", function()
            local content = {
                "void error_case(void) {",
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
