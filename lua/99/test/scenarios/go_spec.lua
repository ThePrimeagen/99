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

    local buffer = test_utils.create_file(content, "go", row, col)
    return p, buffer
end

--- @param buffer number
--- @return string[]
local function r(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("Go Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects and fills a simple function", function()
            local content = {
                "package main",
                "",
                "func greet(name string) string {",
                "}",
            }
            local p, buffer = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "func greet(name string) string {"
            )

            p:resolve(
                "success",
                'func greet(name string) string {\n\treturn "Hello, " + name\n}'
            )
            test_utils.next_frame()

            eq({
                "package main",
                "",
                "func greet(name string) string {",
                '\treturn "Hello, " + name',
                "}",
            }, r(buffer))
        end)

        it("detects function with multiple return values", function()
            local content = {
                "package main",
                "",
                "func divide(a, b int) (int, error) {",
                "}",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "func divide(a, b int) (int, error) {"
            )
        end)

        it("detects function with named return values", function()
            local content = {
                "package main",
                "",
                "func calculate(x int) (result int, err error) {",
                "}",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "func calculate(x int) (result int, err error) {"
            )
        end)
    end)

    describe("comments", function()
        it("includes preceding comment in context", function()
            local content = {
                "package main",
                "",
                "// Greet returns a greeting message",
                "func greet(name string) string {",
                "}",
            }
            local p, _ = setup(content, 4, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "// Greet returns a greeting message"
            )
        end)

        it("includes multi-line comments", function()
            local content = {
                "package main",
                "",
                "// Process handles the data",
                "// and returns the result",
                "func process(data []byte) error {",
                "}",
            }
            local p, _ = setup(content, 5, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "// Process handles the data"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "// and returns the result"
            )
        end)
    end)

    describe("methods", function()
        it("detects method with receiver", function()
            local content = {
                "package main",
                "",
                "type Calculator struct {",
                "\tvalue int",
                "}",
                "",
                "func (c *Calculator) Add(n int) {",
                "}",
            }
            local p, buffer = setup(content, 7, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "func (c *Calculator) Add(n int) {"
            )

            p:resolve(
                "success",
                "func (c *Calculator) Add(n int) {\n\tc.value += n\n}"
            )
            test_utils.next_frame()

            eq({
                "package main",
                "",
                "type Calculator struct {",
                "\tvalue int",
                "}",
                "",
                "func (c *Calculator) Add(n int) {",
                "\tc.value += n",
                "}",
            }, r(buffer))
        end)

        it("detects method with value receiver", function()
            local content = {
                "package main",
                "",
                "type Point struct {",
                "\tx, y int",
                "}",
                "",
                "func (p Point) String() string {",
                "}",
            }
            local p, _ = setup(content, 7, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "func (p Point) String() string {"
            )
        end)
    end)

    describe("interfaces", function()
        it("includes interface definitions in context", function()
            local content = {
                "package main",
                "",
                "type Reader interface {",
                "\tRead(p []byte) (n int, err error)",
                "}",
                "",
                "func readAll(r Reader) ([]byte, error) {",
                "}",
            }
            local p, _ = setup(content, 7, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_exists(query, "Interfaces")
            test_utils.assert_section_contains(
                query,
                "Interfaces",
                "type Reader interface"
            )
        end)

        it("includes multiple interfaces in context", function()
            local content = {
                "package main",
                "",
                "type Reader interface {",
                "\tRead(p []byte) (n int, err error)",
                "}",
                "",
                "type Writer interface {",
                "\tWrite(p []byte) (n int, err error)",
                "}",
                "",
                "func copy(r Reader, w Writer) error {",
                "}",
            }
            local p, _ = setup(content, 11, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_exists(query, "Interfaces")
            test_utils.assert_section_contains(
                query,
                "Interfaces",
                "type Reader interface"
            )
            test_utils.assert_section_contains(
                query,
                "Interfaces",
                "type Writer interface"
            )
        end)
    end)

    describe("closures", function()
        it("detects closure in variable assignment", function()
            local content = {
                "package main",
                "",
                "func main() {",
                "\tdouble := func(x int) int {",
                "\t}",
                "}",
            }
            local p, buffer = setup(content, 4, 12)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "func(x int) int {"
            )

            p:resolve("success", "func(x int) int {\n\t\treturn x * 2\n\t}")
            test_utils.next_frame()

            eq({
                "package main",
                "",
                "func main() {",
                "\tdouble := func(x int) int {",
                "\t\treturn x * 2",
                "\t}",
                "}",
            }, r(buffer))
        end)
    end)

    describe("edge cases", function()
        it("handles empty function body", function()
            local content = {
                "package main",
                "",
                "func empty() {",
                "}",
            }
            local p, buffer = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)

            p:resolve(
                "success",
                'func empty() {\n\tfmt.Println("implemented")\n}'
            )
            test_utils.next_frame()

            eq({
                "package main",
                "",
                "func empty() {",
                '\tfmt.Println("implemented")',
                "}",
            }, r(buffer))
        end)

        it("cancels request when stop_all_requests is called", function()
            local content = {
                "package main",
                "",
                "func cancelMe() {",
                "}",
            }
            local p, buffer = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            assert.is_false(p.request.request:is_cancelled())

            _99.stop_all_requests()
            test_utils.next_frame()

            assert.is_true(p.request.request:is_cancelled())

            p:resolve(
                "success",
                'func cancelMe() {\n\treturn "should not appear"\n}'
            )
            test_utils.next_frame()

            eq(content, r(buffer))
        end)

        it("handles error response gracefully", function()
            local content = {
                "package main",
                "",
                "func errorCase() {",
                "}",
            }
            local p, buffer = setup(content, 3, 0)

            _99.fill_in_function()

            p:resolve("failed", "API error occurred")
            test_utils.next_frame()

            eq(content, r(buffer))
        end)
    end)
end)
