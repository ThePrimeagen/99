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

    local buffer = test_utils.create_file(content, "rust", row, col)
    return p, buffer
end

--- @param buffer number
--- @return string[]
local function r(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("Rust Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("basic functions", function()
        it("detects and fills a simple function", function()
            local content = {
                "fn greet(name: &str) -> String {",
                "}",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "fn greet(name: &str) -> String {"
            )

            p:resolve(
                "success",
                'fn greet(name: &str) -> String {\n    format!("Hello, {}!", name)\n}'
            )
            test_utils.next_frame()

            eq({
                "fn greet(name: &str) -> String {",
                '    format!("Hello, {}!", name)',
                "}",
            }, r(buffer))
        end)

        it("detects pub function", function()
            local content = {
                "pub fn add(a: i32, b: i32) -> i32 {",
                "}",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "pub fn add(a: i32, b: i32) -> i32 {"
            )
        end)

        it("detects async function", function()
            local content = {
                "async fn fetch_data(url: &str) -> Result<String, Error> {",
                "}",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "async fn fetch_data(url: &str)"
            )
        end)

        it("detects function with generics", function()
            local content = {
                "fn first<T>(items: &[T]) -> Option<&T> {",
                "}",
            }
            local p, _ = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "fn first<T>(items: &[T])"
            )
        end)
    end)

    describe("comments", function()
        it("includes doc comment in context", function()
            local content = {
                "/// Greets the user by name",
                "fn greet(name: &str) -> String {",
                "}",
            }
            local p, _ = setup(content, 2, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "/// Greets the user by name"
            )
        end)

        it("includes multi-line doc comments", function()
            local content = {
                "/// Process the input data",
                "/// and return the result",
                "fn process(data: &[u8]) -> Result<(), Error> {",
                "}",
            }
            local p, _ = setup(content, 3, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "/// Process the input data"
            )
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "/// and return the result"
            )
        end)

        it("includes regular comments", function()
            local content = {
                "// Helper function for internal use",
                "fn helper() {",
                "}",
            }
            local p, _ = setup(content, 2, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionDocumentation",
                "// Helper function for internal use"
            )
        end)
    end)

    describe("impl blocks", function()
        it("includes impl header in context (not full body)", function()
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
            local query = p.request.query
            -- Should include impl header but not the full body
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "impl Calculator"
            )
            test_utils.assert_section_contains(
                query,
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
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
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
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "EnclosingContext",
                "impl Greet for Person"
            )
        end)
    end)

    describe("closures", function()
        it("detects closure in variable assignment", function()
            local content = {
                "fn main() {",
                "    let double = |x: i32| -> i32 {",
                "    };",
                "}",
            }
            local p, buffer = setup(content, 2, 18)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "|x: i32| -> i32 {"
            )

            p:resolve("success", "|x: i32| -> i32 {\n        x * 2\n    }")
            test_utils.next_frame()

            eq({
                "fn main() {",
                "    let double = |x: i32| -> i32 {",
                "        x * 2",
                "    };",
                "}",
            }, r(buffer))
        end)

        it("detects simple closure without type annotations", function()
            local content = {
                "fn main() {",
                "    let add = |a, b| {",
                "    };",
                "}",
            }
            local p, _ = setup(content, 2, 15)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            local query = p.request.query
            test_utils.assert_section_contains(
                query,
                "FunctionText",
                "|a, b| {"
            )
        end)
    end)

    describe("edge cases", function()
        it("handles empty function body", function()
            local content = {
                "fn empty() {",
                "}",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)

            p:resolve(
                "success",
                'fn empty() {\n    println!("implemented");\n}'
            )
            test_utils.next_frame()

            eq({
                "fn empty() {",
                '    println!("implemented");',
                "}",
            }, r(buffer))
        end)

        it("cancels request when stop_all_requests is called", function()
            local content = {
                "fn cancel_me() {",
                "}",
            }
            local p, buffer = setup(content, 1, 0)

            _99.fill_in_function()

            assert.is_not_nil(p.request)
            assert.is_false(p.request.request:is_cancelled())

            _99.stop_all_requests()
            test_utils.next_frame()

            assert.is_true(p.request.request:is_cancelled())

            p:resolve("success", 'fn cancel_me() {\n    "should not appear"\n}')
            test_utils.next_frame()

            eq(content, r(buffer))
        end)

        it("handles error response gracefully", function()
            local content = {
                "fn error_case() {",
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
