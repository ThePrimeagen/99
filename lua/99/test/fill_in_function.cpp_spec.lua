---@module "plenary.busted"

-- luacheck: globals describe it assert
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local Levels = require("99.logger.level")
local eq = assert.are.same

--- @param content string[]
--- @param row number
--- @param col number
--- @param lang string?
--- @return _99.test.Provider, number
local function setup(content, row, col, lang)
    assert(lang, "lang must be provided")
    local provider = test_utils.TestProvider.new()
    _99.setup({
        provider = provider,
        logger = {
            error_cache_level = Levels.ERROR,
            type = "print",
        },
    })

    local buffer = test_utils.create_file(content, lang, row, col)
    return provider, buffer
end

--- @param buffer number
--- @return string[]
local function read(buffer)
    return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

describe("fill_in_function", function()
    it("fill in cpp function", function()
        local cpp_content = {
            "",
            "uint32_t test() { }",
        }
        local provider, buffer = setup(cpp_content, 2, 5, "cpp")
        local state = _99.__get_state()

        _99.fill_in_function()

        eq(1, state:active_request_count())
        eq(cpp_content, read(buffer))

        provider:resolve("success", "uint32_t test() {\n    return 42;\n}")
        test_utils.next_frame()

        local expected_state = {
            "",
            "uint32_t test() {",
            "    return 42;",
            "}",
        }
        eq(expected_state, read(buffer))
        eq(0, state:active_request_count())
    end)

    it("fill in cpp concept with requires clause", function()
        local cpp_content = {
            "",
            "template <typename T>",
            "concept Callback = requires(T cb) {",
            "    // Invocation must return an int",
            "};",
        }

        local provider, buffer = setup(cpp_content, 3, 10, "cpp")
        local state = _99.__get_state()

        _99.fill_in_function()

        eq(1, state:active_request_count())
        eq(cpp_content, read(buffer))

        provider:resolve(
            "success",
            "concept Callback = requires(T cb) {\n    { cb() } -> std::same_as<int>;\n};"
        )
        test_utils.next_frame()

        local expected_state = {
            "",
            "template <typename T>",
            "concept Callback = requires(T cb) {",
            "    { cb() } -> std::same_as<int>;",
            "};",
        }
        eq(expected_state, read(buffer))
        eq(0, state:active_request_count())
    end)

    it("fill in nested lambda inside a function", function()
        local cpp_content = {
            "",
            "auto test() -> void",
            "{",
            "    const auto say_42 = []() -> int {",
            "        // TODO: return 42",
            "    };",
            "}",
        }

        local provider, buffer = setup(cpp_content, 4, 20, "cpp")
        local state = _99.__get_state()

        _99.fill_in_function()

        eq(1, state:active_request_count())
        eq(cpp_content, read(buffer))

        provider:resolve(
            "success",
            "const auto say_42 = []() -> int {\n       return 42;\n    };"
        )
        test_utils.next_frame()

        local expected_state = {
            "",
            "auto test() -> void",
            "{",
            "    const auto say_42 = []() -> int {",
            "       return 42;",
            "    };",
            "}",
        }
        eq(expected_state, read(buffer))
        eq(0, state:active_request_count())
    end)
end)
