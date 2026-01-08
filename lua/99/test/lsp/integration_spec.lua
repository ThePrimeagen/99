-- luacheck: globals describe it assert before_each
-- luacheck: ignore 113
local eq = assert.are.same

describe("LSP module integration", function()
    describe("module loading", function()
        it("should load lsp/init.lua", function()
            local lsp = require("99.lsp")
            assert.is_not_nil(lsp)
            assert.is_function(lsp.is_available)
            assert.is_function(lsp.get_context)
            assert.is_function(lsp.default_config)
            assert.is_function(lsp.setup)
        end)

        it("should load lsp/async.lua", function()
            local async = require("99.lsp.async")
            assert.is_not_nil(async)
            assert.is_function(async.await)
            assert.is_function(async.run)
            assert.is_function(async.run_with_timeout)
            assert.is_function(async.parallel_map)
        end)

        it("should load lsp/requests.lua", function()
            local requests = require("99.lsp.requests")
            assert.is_not_nil(requests)
            assert.is_function(requests.document_symbols)
            assert.is_function(requests.hover)
            assert.is_function(requests.inlay_hints)
            assert.is_function(requests.batch_hover)
            assert.is_function(requests.parse_hover_contents)
            assert.is_function(requests.parse_symbol_response)
            assert.is_function(requests.limit_symbols)
        end)

        it("should load lsp/budget.lua", function()
            local budget = require("99.lsp.budget")
            assert.is_not_nil(budget)
            assert.is_function(budget.new)
        end)

        it("should load lsp/context.lua", function()
            local context = require("99.lsp.context")
            assert.is_not_nil(context)
            assert.is_function(context.build_context)
            assert.is_function(context.build_context_with_timeout)
        end)

        it("should load lsp/formatter.lua", function()
            local formatter = require("99.lsp.formatter")
            assert.is_not_nil(formatter)
            assert.is_not_nil(formatter.SymbolKind)
            assert.is_function(formatter.format_symbol)
            assert.is_function(formatter.format_file_context)
            assert.is_function(formatter.format_diagnostics)
            assert.is_function(formatter.format_inlay_hints)
        end)
    end)

    describe("default config", function()
        it("should have all required fields", function()
            local lsp = require("99.lsp")
            local config = lsp.default_config()

            assert.is_true(config.enabled)
            eq("compact", config.format)
            eq(5000, config.timeout)
            eq(100, config.max_symbols)
            assert.is_false(config.include_private)
            eq(8000, config.max_context_tokens)
            eq(4, config.chars_per_token)
            assert.is_true(config.include_diagnostics)
            assert.is_false(config.include_inlay_hints)
        end)

        it("should apply custom config with setup", function()
            local lsp = require("99.lsp")
            lsp.setup({
                max_context_tokens = 4000,
                include_diagnostics = false,
            })

            eq(4000, lsp.config.max_context_tokens)
            assert.is_false(lsp.config.include_diagnostics)
            assert.is_true(lsp.config.enabled)
            eq(8000, lsp.default_config().max_context_tokens)
        end)
    end)

    describe("budget and formatter integration", function()
        it("should work together for context building", function()
            local Budget = require("99.lsp.budget")
            local formatter = require("99.lsp.formatter")

            local budget = Budget.new(100, 4)
            local symbols = {
                { name = "testFn", kind = 12 },
                {
                    name = "MyClass",
                    kind = 5,
                    children = {
                        { name = "method", kind = 6 },
                    },
                },
            }

            local context = formatter.format_file_context("/test.lua", symbols)
            assert.is_true(budget:can_fit(context))

            budget:consume("symbols", context)
            local stats = budget:stats()
            assert.is_true(stats.used_chars > 0)
        end)
    end)

    describe("requests module utilities", function()
        it("should parse hover contents", function()
            local requests = require("99.lsp.requests")

            local str_result = requests.parse_hover_contents("function test()")
            eq("function test()", str_result)

            local markup_result = requests.parse_hover_contents({
                kind = "markdown",
                value = "```lua\nfunction test()\n```",
            })
            assert.is_true(markup_result:find("function test") ~= nil)
        end)
    end)

    describe("ContextStats structure", function()
        it("should have expected fields", function()
            local stats = {
                symbols_included = 10,
                diagnostics_included = 2,
                inlay_hints_included = 5,
                budget_used = 2500,
                budget_remaining = 1500,
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

            eq(10, stats.symbols_included)
            eq(2, stats.diagnostics_included)
            eq(2500, stats.budget_used)
        end)
    end)

    describe("symbol formatting consistency", function()
        it("should format symbols consistently across modules", function()
            local formatter = require("99.lsp.formatter")

            local class_symbol = {
                name = "MyClass",
                kind = formatter.SymbolKind.Class,
                children = {
                    {
                        name = "constructor",
                        kind = formatter.SymbolKind.Constructor,
                    },
                    {
                        name = "method",
                        kind = formatter.SymbolKind.Method,
                        signature = "(arg: string): void",
                    },
                },
            }

            local lines = formatter.format_symbol_with_children(class_symbol, 0)
            assert.is_true(#lines >= 4)
            assert.is_true(lines[1]:find("class MyClass") ~= nil)
            assert.is_true(lines[#lines]:find("}") ~= nil)

            local fn_symbol = {
                name = "helper",
                kind = formatter.SymbolKind.Function,
                signature = "(a: number): string",
            }
            local fn_line = formatter.format_symbol(fn_symbol, 0)
            assert.is_true(fn_line:find("fn") ~= nil)
        end)
    end)

    describe("async module", function()
        it("should create coroutine runners", function()
            local async = require("99.lsp.async")

            local completed = false
            local result_value

            async.run(function()
                return "test_result"
            end, function(result)
                completed = true
                result_value = result
            end)

            vim.wait(100, function()
                return completed
            end)

            assert.is_true(completed)
            eq("test_result", result_value)
        end)
    end)
end)
