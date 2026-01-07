-- luacheck: globals describe it assert
local external = require("99.lsp.external")
local eq = assert.are.same

describe("external", function()
    describe("is_external_uri", function()
        it("should detect node_modules as external", function()
            local uri = "file:///home/user/project/node_modules/lodash/index.js"
            local old_getcwd = vim.fn.getcwd
            vim.fn.getcwd = function()
                return "/home/user/project"
            end

            assert.is_true(external.is_external_uri(uri))

            vim.fn.getcwd = old_getcwd
        end)

        it("should detect site-packages as external", function()
            local uri = "file:///usr/lib/python3/site-packages/requests/__init__.py"
            local old_getcwd = vim.fn.getcwd
            vim.fn.getcwd = function()
                return "/home/user/project"
            end

            assert.is_true(external.is_external_uri(uri))

            vim.fn.getcwd = old_getcwd
        end)

        it("should detect go pkg as external", function()
            local uri = "file:///home/user/go/pkg/mod/github.com/pkg/errors@v0.9.1/errors.go"
            local old_getcwd = vim.fn.getcwd
            vim.fn.getcwd = function()
                return "/home/user/project"
            end

            assert.is_true(external.is_external_uri(uri))

            vim.fn.getcwd = old_getcwd
        end)

        it("should not detect project files as external", function()
            local uri = "file:///home/user/project/src/main.lua"
            local old_getcwd = vim.fn.getcwd
            vim.fn.getcwd = function()
                return "/home/user/project"
            end

            assert.is_false(external.is_external_uri(uri))

            vim.fn.getcwd = old_getcwd
        end)
    end)

    describe("extract_package_name", function()
        it("should extract npm package name", function()
            eq("lodash", external.extract_package_name("/project/node_modules/lodash/index.js"))
        end)

        it("should extract scoped npm package name", function()
            eq(
                "@types/node",
                external.extract_package_name("/project/node_modules/@types/node/index.d.ts")
            )
        end)

        it("should extract python package name", function()
            eq(
                "requests",
                external.extract_package_name("/usr/lib/python3/site-packages/requests/__init__.py")
            )
        end)

        it("should extract go module name", function()
            eq(
                "github.com/pkg/errors",
                external.extract_package_name("/home/user/go/pkg/mod/github.com/pkg/errors@v0.9.1/errors.go")
            )
        end)

        it("should extract lua module name", function()
            eq(
                "luasocket",
                external.extract_package_name("/home/user/.luarocks/share/lua/5.1/luasocket/http.lua")
            )
        end)

        it("should fallback to directory name", function()
            eq("lib", external.extract_package_name("/some/unknown/lib/file.lua"))
        end)
    end)

    describe("get_used_symbols", function()
        it("should find symbols used in content", function()
            local imports = {
                { symbols = { "foo", "bar", "baz" } },
            }

            local old_get_lines = vim.api.nvim_buf_get_lines
            vim.api.nvim_buf_get_lines = function(_, _, _, _)
                return {
                    "local x = foo()",
                    "local y = bar.something",
                    "-- baz is not used",
                }
            end

            local used = external.get_used_symbols(0, imports)

            vim.api.nvim_buf_get_lines = old_get_lines

            assert.is_true(vim.tbl_contains(used, "foo"))
            assert.is_true(vim.tbl_contains(used, "bar"))
        end)
    end)

    describe("format_external_types", function()
        it("should return empty for nil", function()
            eq("", external.format_external_types(nil))
        end)

        it("should return empty for empty array", function()
            eq("", external.format_external_types({}))
        end)

        it("should format types grouped by package", function()
            local types = {
                {
                    symbol_name = "get",
                    type_signature = "(url: string) => Promise<Response>",
                    package_name = "axios",
                    uri = "file:///node_modules/axios/index.d.ts",
                },
                {
                    symbol_name = "post",
                    type_signature = "(url: string, data: any) => Promise<Response>",
                    package_name = "axios",
                    uri = "file:///node_modules/axios/index.d.ts",
                },
                {
                    symbol_name = "map",
                    type_signature = "(arr: T[], fn: (T) => U) => U[]",
                    package_name = "lodash",
                    uri = "file:///node_modules/lodash/index.d.ts",
                },
            }

            local result = external.format_external_types(types)

            assert.is_true(result:find("## External Types") ~= nil)
            assert.is_true(result:find("axios") ~= nil)
            assert.is_true(result:find("lodash") ~= nil)
            assert.is_true(result:find("get:") ~= nil)
            assert.is_true(result:find("post:") ~= nil)
            assert.is_true(result:find("map:") ~= nil)
        end)
    end)
end)

describe("hover type extraction", function()
    local hover = require("99.lsp.hover")

    describe("extract_minimal_type", function()
        it("should return empty for nil", function()
            eq("", hover.extract_minimal_type(nil))
        end)

        it("should extract function signature", function()
            local text = "function foo(a: number, b: string): boolean"
            local result = hover.extract_minimal_type(text)
            assert.is_true(result:find("function foo") ~= nil)
        end)

        it("should truncate long lines", function()
            local long_text = string.rep("x", 150)
            local result = hover.extract_minimal_type(long_text)
            assert.is_true(#result <= 100)
            assert.is_true(result:find("%.%.%.") ~= nil)
        end)
    end)

    describe("extract_type_for_external", function()
        it("should return empty for nil", function()
            eq("", hover.extract_type_for_external(nil))
        end)

        it("should extract function as arrow type", function()
            local text = "function foo(a: number): string"
            local result = hover.extract_type_for_external(text)
            assert.is_true(result:find("=>") ~= nil or result:find("string") ~= nil)
        end)

        it("should handle class types", function()
            local text = "class MyClass extends BaseClass"
            local result = hover.extract_type_for_external(text)
            eq("class MyClass", result)
        end)

        it("should handle interface types", function()
            local text = "interface MyInterface"
            local result = hover.extract_type_for_external(text)
            eq("interface MyInterface", result)
        end)
    end)
end)

describe("imports external detection", function()
    local imports = require("99.lsp.imports")

    describe("is_external_path", function()
        it("should detect node_modules", function()
            local old_getcwd = vim.fn.getcwd
            vim.fn.getcwd = function()
                return "/home/user/project"
            end

            assert.is_true(imports.is_external_path("/other/node_modules/pkg/index.js"))

            vim.fn.getcwd = old_getcwd
        end)

        it("should not detect project files", function()
            local old_getcwd = vim.fn.getcwd
            vim.fn.getcwd = function()
                return "/home/user/project"
            end

            assert.is_false(imports.is_external_path("/home/user/project/src/file.lua"))

            vim.fn.getcwd = old_getcwd
        end)

        it("should handle file:// URIs", function()
            local old_getcwd = vim.fn.getcwd
            vim.fn.getcwd = function()
                return "/home/user/project"
            end

            assert.is_true(
                imports.is_external_path("file:///other/node_modules/pkg/index.js")
            )

            vim.fn.getcwd = old_getcwd
        end)
    end)
end)
