-- luacheck: globals describe it assert before_each
local formatter = require("99.lsp.formatter")
local Budget = require("99.lsp.budget")
local eq = assert.are.same

describe("formatter", function()
    describe("SymbolKind constants", function()
        it("should have correct values", function()
            eq(5, formatter.SymbolKind.Class)
            eq(6, formatter.SymbolKind.Method)
            eq(12, formatter.SymbolKind.Function)
            eq(13, formatter.SymbolKind.Variable)
        end)

        it("should have reverse lookup", function()
            eq("Class", formatter.SymbolKindName[5])
            eq("Method", formatter.SymbolKindName[6])
            eq("Function", formatter.SymbolKindName[12])
        end)
    end)

    describe("kind_to_string", function()
        it("should return lowercase name", function()
            eq("class", formatter.kind_to_string(5))
            eq("function", formatter.kind_to_string(12))
            eq("variable", formatter.kind_to_string(13))
        end)

        it("should return unknown for invalid kind", function()
            eq("unknown", formatter.kind_to_string(999))
        end)
    end)

    describe("kind_to_keyword", function()
        it("should return correct keywords", function()
            eq("class", formatter.kind_to_keyword(5))
            eq("interface", formatter.kind_to_keyword(11))
            eq("fn", formatter.kind_to_keyword(12))
            eq("const", formatter.kind_to_keyword(14))
        end)

        it("should return empty for method/property", function()
            eq("", formatter.kind_to_keyword(6))
            eq("", formatter.kind_to_keyword(7))
        end)

        it("should return empty for unknown kind", function()
            eq("", formatter.kind_to_keyword(999))
        end)
    end)

    describe("is_block_kind", function()
        it("should return true for block kinds", function()
            assert.is_true(formatter.is_block_kind(5)) -- Class
            assert.is_true(formatter.is_block_kind(11)) -- Interface
            assert.is_true(formatter.is_block_kind(23)) -- Struct
            assert.is_true(formatter.is_block_kind(10)) -- Enum
        end)

        it("should return false for non-block kinds", function()
            assert.is_false(formatter.is_block_kind(12)) -- Function
            assert.is_false(formatter.is_block_kind(13)) -- Variable
            assert.is_false(formatter.is_block_kind(6)) -- Method
        end)
    end)

    describe("is_function_kind", function()
        it("should return true for function kinds", function()
            assert.is_true(formatter.is_function_kind(12)) -- Function
            assert.is_true(formatter.is_function_kind(6)) -- Method
            assert.is_true(formatter.is_function_kind(9)) -- Constructor
        end)

        it("should return false for non-function kinds", function()
            assert.is_false(formatter.is_function_kind(5)) -- Class
            assert.is_false(formatter.is_function_kind(13)) -- Variable
        end)
    end)

    describe("format_symbol", function()
        it("should format symbol with signature", function()
            local symbol =
                { name = "test", kind = 12, signature = "(a: number): string" }
            local result = formatter.format_symbol(symbol, 0)
            eq("fn (a: number): string", result)
        end)

        it("should format symbol without signature", function()
            local symbol = { name = "myVar", kind = 13 }
            local result = formatter.format_symbol(symbol, 0)
            eq("myVar", result)
        end)

        it("should add indentation", function()
            local symbol = { name = "nested", kind = 12 }
            local result = formatter.format_symbol(symbol, 2)
            eq("    fn nested", result)
        end)

        it("should use keyword for method", function()
            local symbol =
                { name = "doSomething", kind = 6, signature = "(): void" }
            local result = formatter.format_symbol(symbol, 0)
            eq("(): void", result)
        end)
    end)

    describe("format_symbol_with_children", function()
        it("should format class with children", function()
            local symbol = {
                name = "MyClass",
                kind = 5,
                children = {
                    { name = "init", kind = 9, signature = "()" },
                    {
                        name = "process",
                        kind = 6,
                        signature = "(data: any): void",
                    },
                },
            }
            local lines = formatter.format_symbol_with_children(symbol, 0)
            eq("class MyClass {", lines[1])
            eq("  constructor ()", lines[2])
            eq("  (data: any): void", lines[3])
            eq("}", lines[4])
        end)

        it("should handle nested blocks", function()
            local symbol = {
                name = "OuterClass",
                kind = 5,
                children = {
                    {
                        name = "InnerClass",
                        kind = 5,
                        children = {
                            { name = "method", kind = 6 },
                        },
                    },
                },
            }
            local lines = formatter.format_symbol_with_children(symbol, 0)
            assert.is_true(#lines >= 5)
            assert.is_true(lines[2]:find("InnerClass") ~= nil)
        end)
    end)

    describe("format_file_context", function()
        it("should format complete file context", function()
            local symbols = {
                { name = "fn1", kind = 12 },
                {
                    name = "MyClass",
                    kind = 5,
                    children = {
                        { name = "method", kind = 6 },
                    },
                },
            }
            local result =
                formatter.format_file_context("/test/file.lua", symbols)
            assert.is_true(result:find("=== File: /test/file.lua ===") ~= nil)
            assert.is_true(result:find("Symbols:") ~= nil)
            assert.is_true(result:find("fn1") ~= nil)
            assert.is_true(result:find("MyClass") ~= nil)
        end)
    end)

    describe("format_imports", function()
        it("should format imports with resolved symbols", function()
            local imports = {
                {
                    module_path = "utils",
                    resolved_symbols = {
                        { name = "helper", signature = "(): void" },
                        { name = "format", signature = "(s: string): string" },
                    },
                },
            }
            local result = formatter.format_imports(imports)
            assert.is_true(result:find("Imports:") ~= nil)
            assert.is_true(result:find("from utils:") ~= nil)
            assert.is_true(result:find("%(%): void") ~= nil)
        end)

        it("should use symbol names when no signatures", function()
            local imports = {
                {
                    module_path = "helpers",
                    symbols = { "foo", "bar" },
                },
            }
            local result = formatter.format_imports(imports)
            assert.is_true(result:find("foo, bar") ~= nil)
        end)

        it("should return empty for empty imports", function()
            eq("", formatter.format_imports({}))
        end)
    end)

    describe("format_diagnostic", function()
        it("should format diagnostic with all fields", function()
            local diag = {
                severity = 1,
                lnum = 9,
                col = 4,
                message = "Undefined variable",
                source = "lua_ls",
                code = "undefined-global",
            }
            local result = formatter.format_diagnostic(diag)
            assert.is_true(result:find("%[lua_ls%]") ~= nil)
            assert.is_true(result:find("ERROR") ~= nil)
            assert.is_true(result:find("10:5") ~= nil)
            assert.is_true(result:find("Undefined variable") ~= nil)
            assert.is_true(result:find("%(undefined%-global%)") ~= nil)
        end)

        it("should handle missing optional fields", function()
            local diag =
                { severity = 2, lnum = 0, col = 0, message = "Warning" }
            local result = formatter.format_diagnostic(diag)
            assert.is_true(result:find("WARN") ~= nil)
            assert.is_true(result:find("Warning") ~= nil)
        end)

        it("should use correct severity names", function()
            local diag = { lnum = 0, col = 0, message = "" }
            diag.severity = 1
            assert.is_true(
                formatter.format_diagnostic(diag):find("ERROR") ~= nil
            )
            diag.severity = 2
            assert.is_true(
                formatter.format_diagnostic(diag):find("WARN") ~= nil
            )
            diag.severity = 3
            assert.is_true(
                formatter.format_diagnostic(diag):find("INFO") ~= nil
            )
            diag.severity = 4
            assert.is_true(
                formatter.format_diagnostic(diag):find("HINT") ~= nil
            )
        end)
    end)

    describe("format_diagnostics", function()
        it("should format multiple diagnostics", function()
            local diags = {
                { severity = 1, lnum = 0, col = 0, message = "Error 1" },
                { severity = 2, lnum = 5, col = 0, message = "Warning 1" },
            }
            local result = formatter.format_diagnostics(diags)
            assert.is_true(result:find("Diagnostics:") ~= nil)
            assert.is_true(result:find("Error 1") ~= nil)
            assert.is_true(result:find("Warning 1") ~= nil)
        end)

        it("should return empty for nil", function()
            eq("", formatter.format_diagnostics(nil))
        end)

        it("should return empty for empty array", function()
            eq("", formatter.format_diagnostics({}))
        end)
    end)

    describe("format_external_types", function()
        it("should group types by package", function()
            local types = {
                {
                    symbol_name = "A",
                    type_signature = "class A",
                    package_name = "pkg1",
                },
                {
                    symbol_name = "B",
                    type_signature = "class B",
                    package_name = "pkg1",
                },
                {
                    symbol_name = "C",
                    type_signature = "fn",
                    package_name = "pkg2",
                },
            }
            local result = formatter.format_external_types(types)
            assert.is_true(result:find("External Types:") ~= nil)
            assert.is_true(result:find("pkg1:") ~= nil)
            assert.is_true(result:find("pkg2:") ~= nil)
        end)

        it("should format symbol with type signature", function()
            local types = {
                {
                    symbol_name = "MyClass",
                    type_signature = "class MyClass",
                    package_name = "pkg",
                },
            }
            local result = formatter.format_external_types(types)
            assert.is_true(result:find("MyClass: class MyClass") ~= nil)
        end)

        it("should return empty for nil", function()
            eq("", formatter.format_external_types(nil))
        end)

        it("should return empty for empty array", function()
            eq("", formatter.format_external_types({}))
        end)
    end)

    describe("format_signature_help", function()
        it("should format signature help with signatures", function()
            local sig_help = {
                signatures = {
                    { label = "fn(a: number): void" },
                },
            }
            local result = formatter.format_signature_help(sig_help)
            assert.is_true(result:find("Signature:") ~= nil)
            assert.is_true(result:find("fn%(a: number%): void") ~= nil)
        end)

        it("should include documentation", function()
            local sig_help = {
                signatures = {
                    { label = "fn()", documentation = "Does something useful" },
                },
            }
            local result = formatter.format_signature_help(sig_help)
            assert.is_true(result:find("Does something useful") ~= nil)
        end)

        it("should format multiple signatures", function()
            local sig_help = {
                signatures = {
                    { label = "fn(a: number)" },
                    { label = "fn(a: string)" },
                },
            }
            local result = formatter.format_signature_help(sig_help)
            assert.is_true(result:find("fn%(a: number%)") ~= nil)
            assert.is_true(result:find("fn%(a: string%)") ~= nil)
        end)

        it("should return empty for nil", function()
            eq("", formatter.format_signature_help(nil))
        end)

        it("should return empty for empty signatures", function()
            eq("", formatter.format_signature_help({ signatures = {} }))
        end)

        it("should return empty when no signatures field", function()
            eq("", formatter.format_signature_help({}))
        end)
    end)

    describe("format_with_budget", function()
        local budget

        before_each(function()
            budget = Budget.new(100, 4)
        end)

        it("should return content when within budget", function()
            local content = "Short"
            local result, truncated =
                formatter.format_with_budget(content, budget)
            eq(content, result)
            assert.is_false(truncated)
        end)

        it("should truncate when over budget", function()
            local tiny_budget = Budget.new(3, 1)
            local content = "This is too long"
            local result, truncated =
                formatter.format_with_budget(content, tiny_budget)
            assert.is_true(truncated)
            assert.is_true(#result <= 3)
        end)

        it("should return empty string when no budget remaining", function()
            local full_budget = Budget.new(5, 1)
            full_budget:consume("fill", "12345")
            local result, truncated =
                formatter.format_with_budget("content", full_budget)
            eq("", result)
            assert.is_true(truncated)
        end)

        it("should handle empty content", function()
            local result, truncated = formatter.format_with_budget("", budget)
            eq("", result)
            assert.is_false(truncated)
        end)

        it("should handle nil content", function()
            local result, truncated = formatter.format_with_budget(nil, budget)
            eq("", result)
            assert.is_false(truncated)
        end)
    end)
end)
