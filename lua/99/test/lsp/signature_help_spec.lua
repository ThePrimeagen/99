-- luacheck: globals describe it assert
local signature_help = require("99.lsp.signature_help")
local eq = assert.are.same

describe("signature_help", function()
    describe("format_signature", function()
        it("should return the signature label", function()
            local sig = { label = "foo(a: number, b: string): void" }
            eq(
                "foo(a: number, b: string): void",
                signature_help.format_signature(sig)
            )
        end)
    end)

    describe("format_active_parameter", function()
        it("should return nil for empty signature help", function()
            eq(nil, signature_help.format_active_parameter(nil))
            eq(nil, signature_help.format_active_parameter({}))
            eq(nil, signature_help.format_active_parameter({ signatures = {} }))
        end)

        it("should return nil for signature without parameters", function()
            local sig_help = {
                signatures = { { label = "foo()", parameters = nil } },
                activeSignature = 0,
                activeParameter = 0,
            }
            eq(nil, signature_help.format_active_parameter(sig_help))
        end)

        it("should return active parameter with string label", function()
            local sig_help = {
                signatures = {
                    {
                        label = "foo(a: number, b: string)",
                        parameters = {
                            { label = "a: number" },
                            { label = "b: string" },
                        },
                    },
                },
                activeSignature = 0,
                activeParameter = 1,
            }
            eq("b: string", signature_help.format_active_parameter(sig_help))
        end)

        it("should return active parameter with offset label", function()
            local sig_help = {
                signatures = {
                    {
                        label = "foo(a: number, b: string)",
                        parameters = {
                            { label = { 4, 13 } },
                            { label = { 15, 24 } },
                        },
                    },
                },
                activeSignature = 0,
                activeParameter = 0,
            }
            eq("a: number", signature_help.format_active_parameter(sig_help))
        end)

        it("should use signature-level activeParameter override", function()
            local sig_help = {
                signatures = {
                    {
                        label = "foo(a, b, c)",
                        parameters = {
                            { label = "a" },
                            { label = "b" },
                            { label = "c" },
                        },
                        activeParameter = 2,
                    },
                },
                activeSignature = 0,
                activeParameter = 0,
            }
            eq("c", signature_help.format_active_parameter(sig_help))
        end)
    end)

    describe("get_parameter_names", function()
        it("should return empty for nil input", function()
            eq({}, signature_help.get_parameter_names(nil))
        end)

        it("should extract parameter names from string labels", function()
            local sig_help = {
                signatures = {
                    {
                        label = "fn(x, y, z)",
                        parameters = {
                            { label = "x" },
                            { label = "y" },
                            { label = "z" },
                        },
                    },
                },
                activeSignature = 0,
            }
            eq({ "x", "y", "z" }, signature_help.get_parameter_names(sig_help))
        end)

        it("should extract parameter names from offset labels", function()
            local sig_help = {
                signatures = {
                    {
                        label = "fn(abc, def)",
                        parameters = {
                            { label = { 3, 6 } },
                            { label = { 8, 11 } },
                        },
                    },
                },
                activeSignature = 0,
            }
            eq({ "abc", "def" }, signature_help.get_parameter_names(sig_help))
        end)
    end)

    describe("format_for_context", function()
        it("should return empty for nil input", function()
            eq("", signature_help.format_for_context(nil))
        end)

        it("should format signatures with documentation", function()
            local sig_help = {
                signatures = {
                    {
                        label = "foo(x: number)",
                        documentation = "Does foo things",
                    },
                    {
                        label = "bar(y: string)",
                    },
                },
            }
            local result = signature_help.format_for_context(sig_help)
            assert.is_true(result:find("foo%(x: number%)") ~= nil)
            assert.is_true(result:find("Does foo things") ~= nil)
            assert.is_true(result:find("bar%(y: string%)") ~= nil)
        end)
    end)
end)
