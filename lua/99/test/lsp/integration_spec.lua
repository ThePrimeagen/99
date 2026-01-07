-- luacheck: globals describe it assert before_each
local eq = assert.are.same

describe("LSP module integration", function()
    describe("module loading", function()
        it("should load lsp/init.lua", function()
            local lsp = require("99.lsp")
            assert.is_not_nil(lsp)
            assert.is_function(lsp.is_available)
            assert.is_function(lsp.get_client)
            assert.is_function(lsp.get_context)
            assert.is_function(lsp.default_config)
            assert.is_function(lsp.setup)
        end)

        it("should load lsp/budget.lua", function()
            local budget = require("99.lsp.budget")
            assert.is_not_nil(budget)
            assert.is_function(budget.new)
        end)

        it("should load lsp/cache.lua", function()
            local cache = require("99.lsp.cache")
            assert.is_not_nil(cache)
            assert.is_not_nil(cache.Cache)
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
            assert.is_function(formatter.format_external_types)
            assert.is_function(formatter.format_signature_help)
            assert.is_function(formatter.format_with_budget)
        end)

        it("should load lsp/relevance.lua", function()
            local relevance = require("99.lsp.relevance")
            assert.is_not_nil(relevance)
            assert.is_function(relevance.find_used_symbols)
            assert.is_function(relevance.filter_relevant_imports)
            assert.is_function(relevance.filter_relevant_symbols)
        end)

        it("should load lsp/parallel.lua", function()
            local parallel = require("99.lsp.parallel")
            assert.is_not_nil(parallel)
            assert.is_function(parallel.create_collector)
            assert.is_function(parallel.parallel_map)
            assert.is_function(parallel.parallel_map_with_timeout)
            assert.is_function(parallel.batch_lsp_request)
            assert.is_function(parallel.cancel_all)
            assert.is_function(parallel.wait_all)
            assert.is_function(parallel.race)
        end)

        it("should load lsp/hover.lua", function()
            local hover = require("99.lsp.hover")
            assert.is_not_nil(hover)
            assert.is_function(hover.get_hover)
            assert.is_function(hover.batch_hover)
            assert.is_function(hover.batch_hover_with_timeout)
            assert.is_function(hover.enrich_symbols)
            assert.is_function(hover.extract_type_signature)
            assert.is_function(hover.extract_minimal_type)
            assert.is_function(hover.extract_type_for_external)
        end)

        it("should load lsp/signature_help.lua", function()
            local sig = require("99.lsp.signature_help")
            assert.is_not_nil(sig)
            assert.is_function(sig.get_signature_help)
            assert.is_function(sig.batch_signature_help)
            assert.is_function(sig.batch_signature_help_with_timeout)
            assert.is_function(sig.format_signature)
        end)

        it("should load lsp/type_definition.lua", function()
            local typedef = require("99.lsp.type_definition")
            assert.is_not_nil(typedef)
            assert.is_function(typedef.get_type_definition)
            assert.is_function(typedef.batch_type_definitions)
            assert.is_function(typedef.batch_type_definitions_with_timeout)
        end)

        it("should load lsp/diagnostics.lua", function()
            local diag = require("99.lsp.diagnostics")
            assert.is_not_nil(diag)
            assert.is_function(diag.get_diagnostics)
            assert.is_function(diag.filter_by_severity)
            assert.is_function(diag.filter_by_range)
            assert.is_function(diag.format_diagnostic)
            assert.is_function(diag.get_errors_and_warnings)
        end)

        it("should load lsp/external.lua", function()
            local external = require("99.lsp.external")
            assert.is_not_nil(external)
            assert.is_function(external.is_external_uri)
            assert.is_function(external.extract_package_name)
            assert.is_function(external.identify_external_imports)
            assert.is_function(external.get_external_types)
        end)

        it("should load lsp/symbols.lua", function()
            local symbols = require("99.lsp.symbols")
            assert.is_not_nil(symbols)
            assert.is_function(symbols.get_document_symbols)
            assert.is_function(symbols.limit_symbols)
        end)

        it("should load lsp/imports.lua", function()
            local imports = require("99.lsp.imports")
            assert.is_not_nil(imports)
            assert.is_function(imports.get_imports)
            assert.is_function(imports.is_external_path)
        end)

        it("should load lsp/definitions.lua", function()
            local defs = require("99.lsp.definitions")
            assert.is_not_nil(defs)
            assert.is_function(defs.get_definition)
            assert.is_function(defs.ensure_buffer_loaded)
        end)

        it("should load lsp/fallback.lua", function()
            local fallback = require("99.lsp.fallback")
            assert.is_not_nil(fallback)
            assert.is_function(fallback.is_available)
            assert.is_function(fallback.get_symbols)
            assert.is_function(fallback.get_treesitter_context)
        end)
    end)

    describe("default config", function()
        it("should have all required fields", function()
            local lsp = require("99.lsp")
            local config = lsp.default_config()

            assert.is_true(config.enabled)
            eq(1, config.import_depth)
            eq("compact", config.format)
            eq(5000, config.timeout)
            eq(100, config.max_symbols)
            assert.is_false(config.include_private)
            eq(8000, config.max_context_tokens)
            eq(4, config.chars_per_token)
            assert.is_true(config.include_diagnostics)
            assert.is_true(config.include_external_types)
            eq(3600000, config.external_type_ttl)
            assert.is_true(config.relevance_filter)
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
                { name = "MyClass", kind = 5, children = {
                    { name = "method", kind = 6 },
                } },
            }

            local context = formatter.format_file_context("/test.lua", symbols)
            assert.is_true(budget:can_fit(context))

            budget:consume("symbols", context)
            local stats = budget:stats()
            assert.is_true(stats.used_chars > 0)
        end)
    end)

    describe("relevance and formatter integration", function()
        it("should filter and format imports", function()
            local relevance = require("99.lsp.relevance")
            local formatter = require("99.lsp.formatter")

            local imports = {
                {
                    module_path = "utils",
                    symbols = { "helper", "format" },
                    resolved_symbols = { { name = "helper" }, { name = "format" } },
                },
                {
                    module_path = "unused",
                    symbols = { "notUsed" },
                    resolved_symbols = { { name = "notUsed" } },
                },
            }

            local used = { "helper" }
            local filtered = relevance.filter_relevant_imports(imports, used)
            eq(1, #filtered)
            eq("utils", filtered[1].module_path)

            local formatted = formatter.format_imports(filtered)
            assert.is_true(formatted:find("Imports:") ~= nil)
            assert.is_true(formatted:find("utils") ~= nil)
        end)
    end)

    describe("parallel utilities integration", function()
        it("should work with collect_results pattern", function(done)
            local parallel = require("99.lsp.parallel")

            local add_result, is_done = parallel.create_collector(3, function(results)
                eq("a", results[1])
                eq("b", results[2])
                eq("c", results[3])
                assert.is_true(is_done())
                done()
            end)

            add_result(1, "a", nil)
            add_result(2, "b", nil)
            add_result(3, "c", nil)
        end)
    end)

    describe("ContextStats structure", function()
        it("should have expected fields", function()
            local stats = {
                symbols_included = 10,
                diagnostics_included = 2,
                imports_included = 5,
                imports_filtered = 3,
                external_types_included = 1,
                budget_used = 2500,
                budget_remaining = 1500,
            }

            assert.is_number(stats.symbols_included)
            assert.is_number(stats.diagnostics_included)
            assert.is_number(stats.imports_included)
            assert.is_number(stats.imports_filtered)
            assert.is_number(stats.external_types_included)
            assert.is_number(stats.budget_used)
            assert.is_number(stats.budget_remaining)

            eq(10, stats.symbols_included)
            eq(2, stats.diagnostics_included)
            eq(5, stats.imports_included)
            eq(3, stats.imports_filtered)
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
                    { name = "constructor", kind = formatter.SymbolKind.Constructor },
                    { name = "method", kind = formatter.SymbolKind.Method, signature = "(arg: string): void" },
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
end)
