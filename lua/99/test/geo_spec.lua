-- luacheck: globals describe it assert before_each after_each
local geo = require("99.geo")
local Point = geo.Point
local Range = geo.Range
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

describe("Range", function()
    local buffer

    before_each(function()
        buffer = test_utils.create_file({
            "function foo()",
            "  local x = 1",
            "  return x",
            "end",
            "",
            "function bar()",
            "  return 42",
            "end",
        }, "lua", 1, 0)
    end)

    after_each(function()
        test_utils.clean_files()
    end)

    it("replace text", function()
        local start_point = Point:new(2, 3)
        local end_point = Point:new(3, 11)
        local range = Range:new(buffer, start_point, end_point)
        local original_text = range:to_text()
        eq("local x = 1\n  return x", original_text)

        local replace_text = { "local y = 2" }
        range:replace_text(replace_text)
        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        eq({
            "function foo()",
            "  local y = 2",
            "end",
            "",
            "function bar()",
            "  return 42",
            "end",
        }, lines)
    end)

    it("replace text single line into multi-line", function()
        local start_point = Point:new(2, 3)
        local end_point = Point:new(3, 11)
        local range = Range:new(buffer, start_point, end_point)
        local original_text = range:to_text()
        eq("local x = 1\n  return x", original_text)

        local replace_text = {
            "local y = 2",
            "  local z = 3",
        }
        range:replace_text(replace_text)
        local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
        eq({
            "function foo()",
            "  local y = 2",
            "  local z = 3",
            "end",
            "",
            "function bar()",
            "  return 42",
            "end",
        }, lines)
    end)

    it("should create range from simple visual line selection", function()
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        vim.api.nvim_feedkeys("V", "x", false)

        test_utils.next_frame()
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>gv", true, false, true),
            "x",
            false
        )

        local range = Range.from_visual_selection()
        local text = range:to_text()
        eq("  local x = 1", text)
    end)

    it("should create range from LSP range", function()
        local lsp_range = {
            start = { line = 1, character = 2 },
            ["end"] = { line = 2, character = 10 },
        }
        local range = Range.from_lsp_range(buffer, lsp_range)

        eq(2, range.start.row)
        eq(3, range.start.col)
        eq(3, range.end_.row)
        eq(11, range.end_.col)
        eq(buffer, range.buffer)
    end)
end)

describe("Point", function()
    it("should convert to LSP position (1-based to 0-based)", function()
        local point = Point:new(5, 10)
        local lsp_pos = point:to_lsp_position()

        eq({ line = 4, character = 9 }, lsp_pos)
    end)

    it("should convert to LSP raw values", function()
        local point = Point:new(1, 1)
        local line, char = point:to_lsp()

        eq(0, line)
        eq(0, char)
    end)

    it("should create from LSP position (0-based to 1-based)", function()
        local point = Point:from_lsp_position(3, 7)

        eq(4, point.row)
        eq(8, point.col)
    end)

    it("should roundtrip LSP position conversion", function()
        local original = Point:new(10, 25)
        local lsp_pos = original:to_lsp_position()

        eq({ line = 9, character = 24 }, lsp_pos)

        local restored =
            Point:from_lsp_position(lsp_pos.line, lsp_pos.character)
        eq(original.row, restored.row)
        eq(original.col, restored.col)
    end)

    it("should handle edge case at position (1,1)", function()
        local point = Point:new(1, 1)
        local lsp_pos = point:to_lsp_position()

        eq({ line = 0, character = 0 }, lsp_pos)

        local restored = Point:from_lsp_position(0, 0)
        eq(1, restored.row)
        eq(1, restored.col)
    end)
end)
