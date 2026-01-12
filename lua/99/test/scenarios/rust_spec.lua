-- luacheck: globals describe it assert after_each
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

local function setup(content, row, col)
    return test_utils.setup_test(content, "rust", row, col)
end
local r = test_utils.lines

describe("Rust Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects pub function", function()
            local content = { "pub fn add(a: i32, b: i32) -> i32 {", "}" }
            local p, _ = setup(content, 1, 0)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "pub fn add(a: i32, b: i32) -> i32 {"
            )
        end)

        it("detects function with generics", function()
            local content = { "fn first<T>(items: &[T]) -> Option<&T> {", "}" }
            local p, _ = setup(content, 1, 0)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "fn first<T>(items: &[T])"
            )
        end)
    end)

    describe("comments", function()
        it("includes regular comments", function()
            local content =
                { "// Helper function for internal use", "fn helper() {", "}" }
            local p, _ = setup(content, 2, 0)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionDocumentation",
                "// Helper function for internal use"
            )
        end)
    end)

    describe("impl blocks", function()
        it("includes impl header in context", function()
            local content = {
                "struct Calculator {",
                "    value: i32,",
                "}",
                "",
                "impl Calculator {",
                "    fn new() -> Self {",
                "    }",
                "",
                "    fn add(&mut self, n: i32) {",
                "    }",
                "}",
            }
            local p, buffer = setup(content, 9, 4)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "EnclosingContext",
                "impl Calculator"
            )
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "fn add(&mut self, n: i32) {"
            )

            p:resolve(
                "success",
                "fn add(&mut self, n: i32) {\n        self.value += n;\n    }"
            )
            test_utils.next_frame()
            eq({
                "struct Calculator {",
                "    value: i32,",
                "}",
                "",
                "impl Calculator {",
                "    fn new() -> Self {",
                "    }",
                "",
                "    fn add(&mut self, n: i32) {",
                "        self.value += n;",
                "    }",
                "}",
            }, r(buffer))
        end)

        it("detects method in impl block for trait", function()
            local content = {
                "struct Point {",
                "    x: i32,",
                "    y: i32,",
                "}",
                "",
                "impl Display for Point {",
                "    fn fmt(&self, f: &mut Formatter) -> fmt::Result {",
                "    }",
                "}",
            }
            local p, _ = setup(content, 7, 4)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "EnclosingContext",
                "impl Display for Point"
            )
        end)
    end)

    describe("traits", function()
        it("includes trait context when implementing", function()
            local content = {
                "trait Greet {",
                "    fn greet(&self) -> String;",
                "}",
                "",
                "struct Person {",
                "    name: String,",
                "}",
                "",
                "impl Greet for Person {",
                "    fn greet(&self) -> String {",
                "    }",
                "}",
            }
            local p, _ = setup(content, 10, 4)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "EnclosingContext",
                "impl Greet for Person"
            )
        end)
    end)

    describe("closures", function()
        it("detects simple closure without type annotations", function()
            local content =
                { "fn main() {", "    let add = |a, b| {", "    };", "}" }
            local p, _ = setup(content, 2, 15)
            _99.fill_in_function()
            assert.is_not_nil(p.request)
            test_utils.assert_section_contains(
                p.request.query,
                "FunctionText",
                "|a, b| {"
            )
        end)
    end)
end)
