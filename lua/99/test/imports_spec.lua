-- luacheck: globals describe it assert before_each after_each
local test_utils = require("99.test.test_utils")
local editor = require("99.editor")
local ts = editor.treesitter
local eq = assert.are.same

describe("Treesitter Imports", function()
    after_each(function()
        test_utils.clean_files()
    end)

    describe("imports", function()
        it("should extract imports with aliases", function()
            local buffer = test_utils.create_file({
                'local geo = require("99.geo")',
                'local Logger = require("99.logger.logger")',
                "",
                "local function foo()",
                "    return geo.Point:new(1, 1)",
                "end",
            }, "lua", 1, 0)

            local imports = ts.imports(buffer)

            eq(2, #imports)

            -- Check first import
            eq("geo", imports[1].alias)
            eq("99.geo", imports[1].path)

            -- Check second import
            eq("Logger", imports[2].alias)
            eq("99.logger.logger", imports[2].path)
        end)

        it("should return empty list when no imports", function()
            local buffer = test_utils.create_file({
                "local function foo()",
                "    return 42",
                "end",
            }, "lua", 1, 0)

            local imports = ts.imports(buffer)
            eq(0, #imports)
        end)

        it("should handle imports without assignments", function()
            local buffer = test_utils.create_file({
                'require("some.module")',
                "",
                "local x = 1",
            }, "lua", 1, 0)

            local imports = ts.imports(buffer)

            -- Should still find the require call
            eq(1, #imports)
            eq("some.module", imports[1].path)
            -- No alias for standalone require
            eq(nil, imports[1].alias)
        end)

        it("should handle multiple imports on same file", function()
            local buffer = test_utils.create_file({
                'local a = require("module.a")',
                'local b = require("module.b")',
                'local c = require("module.c")',
                "",
                "return { a = a, b = b, c = c }",
            }, "lua", 1, 0)

            local imports = ts.imports(buffer)
            eq(3, #imports)
        end)
    end)
end)
