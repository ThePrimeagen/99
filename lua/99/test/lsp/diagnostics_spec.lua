-- luacheck: globals describe it assert before_each
local diagnostics = require("99.lsp.diagnostics")
local geo = require("99.geo")
local eq = assert.are.same

describe("diagnostics", function()
    describe("filter_by_severity", function()
        local diags

        before_each(function()
            diags = {
                { severity = 1, message = "error1" },
                { severity = 2, message = "warn1" },
                { severity = 3, message = "info1" },
                { severity = 4, message = "hint1" },
            }
        end)

        it("should filter to errors only", function()
            local filtered = diagnostics.filter_by_severity(diags, 1)
            eq(1, #filtered)
            eq("error1", filtered[1].message)
        end)

        it("should filter to errors and warnings", function()
            local filtered = diagnostics.filter_by_severity(diags, 2)
            eq(2, #filtered)
        end)

        it("should include all with severity 4", function()
            local filtered = diagnostics.filter_by_severity(diags, 4)
            eq(4, #filtered)
        end)
    end)

    describe("filter_by_range", function()
        it("should filter diagnostics within range", function()
            local diags_list = {
                { lnum = 5, col = 0, message = "in range" },
                { lnum = 15, col = 0, message = "out of range" },
                { lnum = 10, col = 5, message = "also in range" },
            }
            local range =
                geo.Range:new(0, geo.Point:new(5, 1), geo.Point:new(12, 100))
            local filtered = diagnostics.filter_by_range(diags_list, range)
            eq(2, #filtered)
            eq("in range", filtered[1].message)
            eq("also in range", filtered[2].message)
        end)
    end)

    describe("convert_to_point", function()
        it("should convert 0-based diagnostic to 1-based Point", function()
            local diag = { lnum = 9, col = 4 }
            local point = diagnostics.convert_to_point(diag)
            eq(10, point.row)
            eq(5, point.col)
        end)
    end)

    describe("format_diagnostic", function()
        it("should format diagnostic with all fields", function()
            local diag = {
                severity = 1,
                lnum = 9,
                col = 4,
                message = "Something is wrong",
                source = "lua_ls",
                code = "undefined-global",
            }
            local result = diagnostics.format_diagnostic(diag)
            assert.is_true(result:find("lua_ls") ~= nil)
            assert.is_true(result:find("ERROR") ~= nil)
            assert.is_true(result:find("10:5") ~= nil)
            assert.is_true(result:find("Something is wrong") ~= nil)
            assert.is_true(result:find("undefined%-global") ~= nil)
        end)

        it("should format diagnostic without optional fields", function()
            local diag = {
                severity = 2,
                lnum = 0,
                col = 0,
                message = "Warning message",
            }
            local result = diagnostics.format_diagnostic(diag)
            assert.is_true(result:find("WARN") ~= nil)
            assert.is_true(result:find("1:1") ~= nil)
            assert.is_true(result:find("Warning message") ~= nil)
        end)
    end)

    describe("format_diagnostics", function()
        it("should return empty for nil", function()
            eq("", diagnostics.format_diagnostics(nil))
        end)

        it("should return empty for empty array", function()
            eq("", diagnostics.format_diagnostics({}))
        end)

        it("should format multiple diagnostics", function()
            local diags_list = {
                { severity = 1, lnum = 0, col = 0, message = "Error 1" },
                { severity = 2, lnum = 5, col = 10, message = "Warning 1" },
            }
            local result = diagnostics.format_diagnostics(diags_list)
            assert.is_true(result:find("Error 1") ~= nil)
            assert.is_true(result:find("Warning 1") ~= nil)
        end)
    end)

    describe("format_for_context", function()
        it("should format with header", function()
            local diags_list = {
                { severity = 1, lnum = 0, col = 0, message = "Test error" },
            }
            local result = diagnostics.format_for_context(diags_list)
            assert.is_true(result:find("## Diagnostics") ~= nil)
            assert.is_true(result:find("Test error") ~= nil)
        end)
    end)

    describe("get_counts", function()
        it("should count diagnostics by severity", function()
            local diags_list = {
                { severity = 1 },
                { severity = 1 },
                { severity = 2 },
                { severity = 3 },
                { severity = 4 },
                { severity = 4 },
            }
            local counts = diagnostics.get_counts(diags_list)
            eq(2, counts.errors)
            eq(1, counts.warnings)
            eq(1, counts.info)
            eq(2, counts.hints)
        end)
    end)

    describe("group_by_severity", function()
        it("should group diagnostics", function()
            local diags_list = {
                { severity = 1, message = "e1" },
                { severity = 2, message = "w1" },
                { severity = 1, message = "e2" },
            }
            local groups = diagnostics.group_by_severity(diags_list)
            eq(2, #groups[1])
            eq(1, #groups[2])
        end)
    end)
end)
