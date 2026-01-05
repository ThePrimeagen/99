-- luacheck: globals describe it assert before_each after_each
local test_utils = require("99.test.test_utils")
local editor = require("99.editor")
local lsp = editor.lsp
local eq = assert.are.same

describe("LSP Module", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("has_lsp", function()
        it("should return false when no LSP is attached", function()
            local buffer = test_utils.create_file({
                "local x = 1",
                "return x",
            }, "lua", 1, 0)

            local result = lsp.has_lsp(buffer)
            eq(false, result)
        end)
    end)

    describe("extract_identifiers", function()
        it("should extract identifiers from a range", function()
            local buffer = test_utils.create_file({
                "local geo = require('99.geo')",
                "local Point = geo.Point",
                "",
                "local function foo()",
                "    local cursor = Point:from_cursor()",
                "    return cursor",
                "end",
            }, "lua", 1, 0)

            local geo = require("99.geo")
            local Point = geo.Point
            local Range = geo.Range

            -- Range covering the function body (lines 5-6)
            local start_point = Point:new(5, 1)
            local end_point = Point:new(6, 17)
            local range = Range:new(buffer, start_point, end_point)

            local identifiers = lsp.extract_identifiers(buffer, range)

            -- Should find identifiers in the range
            assert(#identifiers > 0, "Should find at least one identifier")

            -- Verify we found expected identifiers
            local found_names = {}
            for _, ident in ipairs(identifiers) do
                found_names[ident.name] = true
            end

            assert(found_names["cursor"], "Should find 'cursor' identifier")
        end)

        it("should return empty list when no identifiers in range", function()
            local buffer = test_utils.create_file({
                "-- just a comment",
                "",
                "-- another comment",
            }, "lua", 1, 0)

            local geo = require("99.geo")
            local Point = geo.Point
            local Range = geo.Range

            local start_point = Point:new(1, 1)
            local end_point = Point:new(3, 20)
            local range = Range:new(buffer, start_point, end_point)

            local identifiers = lsp.extract_identifiers(buffer, range)
            eq(0, #identifiers)
        end)
    end)

    describe("format_type_context", function()
        it("should format empty type info as empty string", function()
            local result = lsp.format_type_context({})
            eq("", result)
        end)

        it("should format nil type info as empty string", function()
            local result = lsp.format_type_context(nil)
            eq("", result)
        end)

        it("should format type info correctly", function()
            local type_info = {
                foo = "function(x: number): string",
                bar = "number",
            }

            local result = lsp.format_type_context(type_info)

            assert(
                result:match("<TypeContext>"),
                "Should start with TypeContext tag"
            )
            assert(
                result:match("</TypeContext>"),
                "Should end with TypeContext tag"
            )
            assert(result:match("foo:"), "Should contain foo")
            assert(result:match("bar:"), "Should contain bar")
        end)
    end)
end)
