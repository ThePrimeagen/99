-- luacheck: globals describe it assert before_each after_each
local context = require("99.lsp.context")
local formatter = require("99.lsp.formatter")
local Budget = require("99.lsp.budget")
local eq = assert.are.same

describe("context", function()
    describe("_format_and_return", function()
        local request_context
        local budget
        local stats
        local logger

        before_each(function()
            request_context = {
                full_path = "/test/file.lua",
            }
            budget = Budget.new(1000, 4)
            stats = {
                symbols_included = 0,
                diagnostics_included = 0,
                imports_included = 0,
                imports_filtered = 0,
                external_types_included = 0,
                budget_used = 0,
                budget_remaining = 0,
            }
            logger = {
                debug = function() end,
            }
        end)

        it("should format symbols context", function(done)
            local symbols = {
                { name = "testFn", kind = 12, signature = "(a: number): string" },
            }

            context._format_and_return(
                request_context,
                symbols,
                {},
                {},
                {},
                budget,
                stats,
                logger,
                function(result, err, result_stats)
                    assert.is_nil(err)
                    assert.is_not_nil(result)
                    assert.is_true(result:find("File: /test/file.lua") ~= nil)
                    assert.is_true(result:find("testFn") ~= nil)
                    assert.is_true(result_stats.budget_used > 0)
                    done()
                end
            )
        end)

        it("should include diagnostics in output", function(done)
            local symbols = {
                { name = "fn", kind = 12 },
            }
            local diagnostics = {
                { severity = 1, lnum = 5, col = 0, message = "Test error" },
            }

            context._format_and_return(
                request_context,
                symbols,
                {},
                diagnostics,
                {},
                budget,
                stats,
                logger,
                function(result, err, _)
                    assert.is_nil(err)
                    assert.is_true(result:find("Diagnostics") ~= nil)
                    assert.is_true(result:find("Test error") ~= nil)
                    done()
                end
            )
        end)

        it("should include imports in output", function(done)
            local symbols = {
                { name = "fn", kind = 12 },
            }
            local imports = {
                {
                    module_path = "utils",
                    resolved_symbols = { { name = "helper", signature = "(): void" } },
                },
            }

            context._format_and_return(
                request_context,
                symbols,
                imports,
                {},
                {},
                budget,
                stats,
                logger,
                function(result, err, _)
                    assert.is_nil(err)
                    assert.is_true(result:find("Imports") ~= nil)
                    assert.is_true(result:find("utils") ~= nil)
                    done()
                end
            )
        end)

        it("should include external types in output", function(done)
            local symbols = {
                { name = "fn", kind = 12 },
            }
            local external_types = {
                {
                    symbol_name = "ExternalClass",
                    type_signature = "class ExternalClass",
                    package_name = "external-pkg",
                },
            }

            context._format_and_return(
                request_context,
                symbols,
                {},
                {},
                external_types,
                budget,
                stats,
                logger,
                function(result, err, _)
                    assert.is_nil(err)
                    assert.is_true(result:find("External Types") ~= nil)
                    assert.is_true(result:find("external%-pkg") ~= nil)
                    done()
                end
            )
        end)

        it("should track budget usage in stats", function(done)
            local symbols = {
                { name = "fn1", kind = 12 },
                { name = "fn2", kind = 12 },
            }

            context._format_and_return(
                request_context,
                symbols,
                {},
                {},
                {},
                budget,
                stats,
                logger,
                function(_, _, result_stats)
                    assert.is_true(result_stats.budget_used > 0)
                    assert.is_true(result_stats.budget_remaining > 0)
                    eq(result_stats.budget_used + result_stats.budget_remaining,
                        1000 * 4)
                    done()
                end
            )
        end)

        it("should truncate content when budget exceeded", function(done)
            local small_budget = Budget.new(10, 1)
            local symbols = {
                { name = "veryLongFunctionNameThatExceedsBudget", kind = 12 },
            }

            context._format_and_return(
                request_context,
                symbols,
                {},
                {},
                {},
                small_budget,
                stats,
                logger,
                function(result, err, _)
                    assert.is_nil(err)
                    assert.is_true(#result <= 13)
                    done()
                end
            )
        end)
    end)
end)

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

    describe("format_external_types", function()
        it("should format external types grouped by package", function()
            local types = {
                { symbol_name = "ClassA", type_signature = "class", package_name = "pkg1" },
                { symbol_name = "ClassB", type_signature = "class", package_name = "pkg1" },
                { symbol_name = "FuncC", type_signature = "() => void", package_name = "pkg2" },
            }
            local result = formatter.format_external_types(types)
            assert.is_true(result:find("External Types") ~= nil)
            assert.is_true(result:find("pkg1") ~= nil)
            assert.is_true(result:find("pkg2") ~= nil)
            assert.is_true(result:find("ClassA") ~= nil)
            assert.is_true(result:find("FuncC") ~= nil)
        end)

        it("should return empty string for empty array", function()
            eq("", formatter.format_external_types({}))
        end)

        it("should return empty string for nil", function()
            eq("", formatter.format_external_types(nil))
        end)
    end)

    describe("format_signature_help", function()
        it("should format signature help", function()
            local sig_help = {
                signatures = {
                    { label = "fn(a: number, b: string): boolean" },
                    { label = "fn(a: number): void", documentation = "Overload docs" },
                },
            }
            local result = formatter.format_signature_help(sig_help)
            assert.is_true(result:find("Signature") ~= nil)
            assert.is_true(result:find("fn%(a: number, b: string%)") ~= nil)
            assert.is_true(result:find("Overload docs") ~= nil)
        end)

        it("should return empty for nil", function()
            eq("", formatter.format_signature_help(nil))
        end)

        it("should return empty for empty signatures", function()
            eq("", formatter.format_signature_help({ signatures = {} }))
        end)
    end)

    describe("format_with_budget", function()
        it("should return content unchanged when within budget", function()
            local budget = Budget.new(1000, 4)
            local content = "Short content"
            local result, truncated = formatter.format_with_budget(content, budget)
            eq(content, result)
            assert.is_false(truncated)
        end)

        it("should truncate content when over budget", function()
            local budget = Budget.new(5, 1)
            budget:consume("test", "fill")
            local content = "This is a very long content string"
            local result, truncated = formatter.format_with_budget(content, budget)
            assert.is_true(truncated)
            assert.is_true(#result < #content)
            assert.is_true(result:find("%.%.%.$") ~= nil)
        end)

        it("should return empty when no budget remaining", function()
            local budget = Budget.new(5, 1)
            budget:consume("test", "12345")
            local result, truncated = formatter.format_with_budget("more content", budget)
            eq("", result)
            assert.is_true(truncated)
        end)

        it("should handle empty content", function()
            local budget = Budget.new(100, 4)
            local result, truncated = formatter.format_with_budget("", budget)
            eq("", result)
            assert.is_false(truncated)
        end)

        it("should handle nil content", function()
            local budget = Budget.new(100, 4)
            local result, truncated = formatter.format_with_budget(nil, budget)
            eq("", result)
            assert.is_false(truncated)
        end)
    end)
end)

describe("ContextStats tracking", function()
    it("should have all required fields", function()
        local stats = {
            symbols_included = 5,
            diagnostics_included = 2,
            imports_included = 3,
            imports_filtered = 7,
            external_types_included = 4,
            budget_used = 1500,
            budget_remaining = 2500,
        }
        assert.is_number(stats.symbols_included)
        assert.is_number(stats.diagnostics_included)
        assert.is_number(stats.imports_included)
        assert.is_number(stats.imports_filtered)
        assert.is_number(stats.external_types_included)
        assert.is_number(stats.budget_used)
        assert.is_number(stats.budget_remaining)
    end)
end)
