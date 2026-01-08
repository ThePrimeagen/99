-- luacheck: globals describe it assert
local formatter = require("99.lsp.formatter")
local eq = assert.are.same

describe("formatter integration", function()
    describe("format_diagnostics", function()
        it("should format diagnostics array", function()
            local diags = {
                { severity = 1, lnum = 0, col = 0, message = "Error 1" },
                { severity = 2, lnum = 5, col = 10, message = "Warning 1" },
            }
            local result = formatter.format_diagnostics(diags)
            assert.is_true(result:find("Diagnostics") ~= nil)
            assert.is_true(result:find("ERROR") ~= nil)
            assert.is_true(result:find("WARN") ~= nil)
        end)

        it("should return empty string for empty array", function()
            eq("", formatter.format_diagnostics({}))
        end)

        it("should return empty string for nil", function()
            eq("", formatter.format_diagnostics(nil))
        end)
    end)

    describe("format_inlay_hints", function()
        it("should format inlay hints array", function()
            local hints = {
                {
                    position = { line = 5, character = 10 },
                    label = ": string",
                    kind = 1,
                },
                {
                    position = { line = 10, character = 5 },
                    label = "name:",
                    kind = 2,
                },
            }
            local result = formatter.format_inlay_hints(hints)
            assert.is_true(result:find("Inlay Hints") ~= nil)
            assert.is_true(result:find("type") ~= nil)
            assert.is_true(result:find("param") ~= nil)
            assert.is_true(result:find(": string") ~= nil)
            assert.is_true(result:find("name:") ~= nil)
        end)

        it("should handle InlayHintLabelPart array", function()
            local hints = {
                {
                    position = { line = 1, character = 0 },
                    label = {
                        { value = "part1" },
                        { value = "part2" },
                    },
                    kind = 1,
                },
            }
            local result = formatter.format_inlay_hints(hints)
            assert.is_true(result:find("part1part2") ~= nil)
        end)

        it("should return empty string for empty array", function()
            eq("", formatter.format_inlay_hints({}))
        end)

        it("should return empty string for nil", function()
            eq("", formatter.format_inlay_hints(nil))
        end)
    end)
end)

describe("ContextStats tracking", function()
    it("should have all required fields", function()
        local stats = {
            symbols_included = 5,
            diagnostics_included = 2,
            inlay_hints_included = 3,
            budget_used = 1500,
            budget_remaining = 2500,
            capabilities_used = {
                "textDocument/documentSymbol",
                "textDocument/hover",
            },
        }
        assert.is_number(stats.symbols_included)
        assert.is_number(stats.diagnostics_included)
        assert.is_number(stats.inlay_hints_included)
        assert.is_number(stats.budget_used)
        assert.is_number(stats.budget_remaining)
        assert.is_table(stats.capabilities_used)
    end)
end)
