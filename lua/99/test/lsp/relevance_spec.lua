-- luacheck: globals describe it assert before_each
local relevance = require("99.lsp.relevance")
local eq = assert.are.same

describe("relevance", function()
    describe("is_keyword", function()
        it("should recognize Lua keywords", function()
            assert.is_true(relevance.is_keyword("function"))
            assert.is_true(relevance.is_keyword("local"))
            assert.is_true(relevance.is_keyword("return"))
            assert.is_true(relevance.is_keyword("end"))
        end)

        it("should recognize TypeScript keywords", function()
            assert.is_true(relevance.is_keyword("const"))
            assert.is_true(relevance.is_keyword("interface"))
            assert.is_true(relevance.is_keyword("async"))
            assert.is_true(relevance.is_keyword("await"))
        end)

        it("should recognize Python keywords", function()
            assert.is_true(relevance.is_keyword("def"))
            assert.is_true(relevance.is_keyword("self"))
            assert.is_true(relevance.is_keyword("lambda"))
        end)

        it("should recognize Go keywords", function()
            assert.is_true(relevance.is_keyword("func"))
            assert.is_true(relevance.is_keyword("defer"))
            assert.is_true(relevance.is_keyword("go"))
        end)

        it("should not flag regular identifiers as keywords", function()
            assert.is_false(relevance.is_keyword("myFunction"))
            assert.is_false(relevance.is_keyword("UserService"))
            assert.is_false(relevance.is_keyword("getData"))
        end)
    end)

    describe("filter_relevant_imports", function()
        local imports

        before_each(function()
            imports = {
                {
                    module_path = "utils",
                    symbols = { "format", "parse" },
                    resolved_symbols = { { name = "format" }, { name = "parse" } },
                },
                {
                    module_path = "helpers",
                    symbols = { "calculate", "validate" },
                    resolved_symbols = { { name = "calculate" }, { name = "validate" } },
                },
                {
                    module_path = "constants",
                    symbols = { "MAX_VALUE", "MIN_VALUE" },
                    resolved_symbols = { { name = "MAX_VALUE" }, { name = "MIN_VALUE" } },
                },
            }
        end)

        it("should return empty for empty imports", function()
            eq({}, relevance.filter_relevant_imports({}, { "format" }))
        end)

        it("should return all imports when no used symbols provided", function()
            local result = relevance.filter_relevant_imports(imports, {})
            eq(3, #result)
        end)

        it("should return all imports when used_symbols is nil", function()
            local result = relevance.filter_relevant_imports(imports, nil)
            eq(3, #result)
        end)

        it("should filter to only imports with used symbols", function()
            local used = { "format", "calculate" }
            local result = relevance.filter_relevant_imports(imports, used)
            eq(2, #result)
            eq("utils", result[1].module_path)
            eq("helpers", result[2].module_path)
        end)

        it("should match resolved_symbols by name", function()
            local used = { "MAX_VALUE" }
            local result = relevance.filter_relevant_imports(imports, used)
            eq(1, #result)
            eq("constants", result[1].module_path)
        end)

        it("should filter out imports with no used symbols", function()
            local used = { "nonexistent" }
            local result = relevance.filter_relevant_imports(imports, used)
            eq(0, #result)
        end)
    end)

    describe("filter_relevant_symbols", function()
        local symbols

        before_each(function()
            symbols = {
                { name = "MyClass", kind = 5, children = {
                    { name = "init", kind = 6 },
                    { name = "process", kind = 6 },
                } },
                { name = "helperFn", kind = 12 },
                { name = "CONSTANT", kind = 14 },
            }
        end)

        it("should return empty for empty symbols", function()
            eq({}, relevance.filter_relevant_symbols({}, { "MyClass" }))
        end)

        it("should return all symbols when no used symbols provided", function()
            local result = relevance.filter_relevant_symbols(symbols, {})
            eq(3, #result)
        end)

        it("should filter to matching symbols", function()
            local used = { "helperFn" }
            local result = relevance.filter_relevant_symbols(symbols, used)
            eq(1, #result)
            eq("helperFn", result[1].name)
        end)

        it("should include parent symbols with relevant children", function()
            local used = { "init" }
            local result = relevance.filter_relevant_symbols(symbols, used)
            eq(1, #result)
            eq("MyClass", result[1].name)
            eq(1, #result[1].children)
            eq("init", result[1].children[1].name)
        end)
    end)

    describe("calculate_import_relevance", function()
        it("should return 0 when no used symbols", function()
            local import = { symbols = { "foo", "bar" } }
            eq(0, relevance.calculate_import_relevance(import, {}))
        end)

        it("should return 0 when used_symbols is nil", function()
            local import = { symbols = { "foo", "bar" } }
            eq(0, relevance.calculate_import_relevance(import, nil))
        end)

        it("should score 10 per matching symbol", function()
            local import = { symbols = { "foo", "bar", "baz" } }
            local used = { "foo", "bar" }
            eq(20, relevance.calculate_import_relevance(import, used))
        end)

        it("should score 5 per matching resolved_symbol", function()
            local import = {
                symbols = {},
                resolved_symbols = { { name = "foo" }, { name = "bar" } },
            }
            local used = { "foo" }
            eq(5, relevance.calculate_import_relevance(import, used))
        end)

        it("should combine symbol and resolved_symbol scores", function()
            local import = {
                symbols = { "foo" },
                resolved_symbols = { { name = "bar" } },
            }
            local used = { "foo", "bar" }
            eq(15, relevance.calculate_import_relevance(import, used))
        end)
    end)

    describe("sort_imports_by_relevance", function()
        it("should return empty for empty imports", function()
            eq({}, relevance.sort_imports_by_relevance({}, { "foo" }))
        end)

        it("should sort imports by relevance score", function()
            local imports = {
                { module_path = "low", symbols = { "unused" } },
                { module_path = "high", symbols = { "foo", "bar", "baz" } },
                { module_path = "medium", symbols = { "foo" } },
            }
            local used = { "foo", "bar", "baz" }
            local result = relevance.sort_imports_by_relevance(imports, used)
            eq("high", result[1].module_path)
            eq("medium", result[2].module_path)
            eq("low", result[3].module_path)
        end)
    end)
end)
