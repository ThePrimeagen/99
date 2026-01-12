-- luacheck: globals describe it assert after_each
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

local function setup(content, row, col)
    return test_utils.setup_test(content, "go", row, col)
end
local r = test_utils.lines

describe("Go Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
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
            test_utils.assert_section_contains(
                p.request.query,
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
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "func calculate(x int) (result int, err error) {"
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
            test_utils.assert_section_contains(
                p.request.query,
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
            test_utils.assert_section_contains(
                p.request.query,
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
            test_utils.assert_section_exists(p.request.query, "Interfaces")
            test_utils.assert_section_contains(
                p.request.query,
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
            test_utils.assert_section_exists(p.request.query, "Interfaces")
            test_utils.assert_section_contains(
                p.request.query,
                "Interfaces",
                "type Reader interface"
            )
            test_utils.assert_section_contains(
                p.request.query,
                "Interfaces",
                "type Writer interface"
            )
        end)
    end)
end)
