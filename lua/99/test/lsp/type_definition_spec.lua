-- luacheck: globals describe it assert
local type_definition = require("99.lsp.type_definition")
local eq = assert.are.same

describe("type_definition", function()
    describe("parse_type_definition_response", function()
        it("should return empty array for nil", function()
            eq({}, type_definition.parse_type_definition_response(nil))
        end)

        it("should parse single Location", function()
            local result = {
                uri = "file:///test.lua",
                range = {
                    start = { line = 10, character = 5 },
                    ["end"] = { line = 10, character = 15 },
                },
            }
            local defs = type_definition.parse_type_definition_response(result)
            eq(1, #defs)
            eq("file:///test.lua", defs[1].uri)
            eq("/test.lua", defs[1].file_path)
            eq(10, defs[1].range.start.line)
        end)

        it("should parse Location array", function()
            local result = {
                {
                    uri = "file:///a.lua",
                    range = {
                        start = { line = 1, character = 0 },
                        ["end"] = { line = 1, character = 10 },
                    },
                },
                {
                    uri = "file:///b.lua",
                    range = {
                        start = { line = 5, character = 0 },
                        ["end"] = { line = 5, character = 20 },
                    },
                },
            }
            local defs = type_definition.parse_type_definition_response(result)
            eq(2, #defs)
            eq("file:///a.lua", defs[1].uri)
            eq("file:///b.lua", defs[2].uri)
        end)

        it("should parse LocationLink array", function()
            local result = {
                {
                    targetUri = "file:///target.lua",
                    targetRange = {
                        start = { line = 20, character = 0 },
                        ["end"] = { line = 25, character = 0 },
                    },
                    targetSelectionRange = {
                        start = { line = 20, character = 5 },
                        ["end"] = { line = 20, character = 15 },
                    },
                    originSelectionRange = {
                        start = { line = 1, character = 0 },
                        ["end"] = { line = 1, character = 5 },
                    },
                },
            }
            local defs = type_definition.parse_type_definition_response(result)
            eq(1, #defs)
            eq("file:///target.lua", defs[1].uri)
            eq(20, defs[1].range.start.line)
            eq(20, defs[1].target_selection_range.start.line)
        end)
    end)

    describe("format_for_context", function()
        it("should format definition with location", function()
            local def = {
                uri = "file:///test.lua",
                file_path = "/test.lua",
                range = {
                    start = { line = 9, character = 4 },
                    ["end"] = { line = 9, character = 10 },
                },
            }
            local result = type_definition.format_for_context(def)
            eq("/test.lua:10:5", result)
        end)

        it("should handle missing range", function()
            local def = {
                uri = "file:///test.lua",
                file_path = "/test.lua",
            }
            local result = type_definition.format_for_context(def)
            eq("/test.lua", result)
        end)
    end)
end)
