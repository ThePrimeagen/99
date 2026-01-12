-- luacheck: globals describe it assert after_each
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local shared = require("99.test.scenarios.shared_tests")
local eq = assert.are.same

local langs = { "c", "python", "go", "ruby", "rust", "lua", "typescript" }

describe("Common Scenarios", function()
    after_each(function()
        test_utils.clean_files()
    end)

    for _, lang in ipairs(langs) do
        describe(lang, function()
            describe("basic functions", function()
                it("detects and fills a simple function", function()
                    local d = shared.simple_function[lang]
                    local p, buffer =
                        test_utils.setup_test(d.code, lang, d.row, d.col)
                    _99.fill_in_function()
                    assert.is_not_nil(p.request)
                    test_utils.assert_section_contains(
                        p.request.query,
                        "FunctionText",
                        d.check
                    )
                    p:resolve("success", d.resolve)
                    test_utils.next_frame()
                    eq(d.expect, test_utils.lines(buffer))
                end)
            end)

            describe("comments", function()
                it("includes preceding comment in context", function()
                    local d = shared.single_comment[lang]
                    local p, _ =
                        test_utils.setup_test(d.code, lang, d.row, d.col)
                    _99.fill_in_function()
                    assert.is_not_nil(p.request)
                    test_utils.assert_section_contains(
                        p.request.query,
                        "FunctionDocumentation",
                        d.check
                    )
                end)

                it("includes multi-line comments", function()
                    local d = shared.multi_line_comment[lang]
                    local p, _ =
                        test_utils.setup_test(d.code, lang, d.row, d.col)
                    _99.fill_in_function()
                    assert.is_not_nil(p.request)
                    for _, check in ipairs(d.checks) do
                        test_utils.assert_section_contains(
                            p.request.query,
                            "FunctionDocumentation",
                            check
                        )
                    end
                end)
            end)

            describe("edge cases", function()
                it(
                    "cancels request when stop_all_requests is called",
                    function()
                        local d = shared.simple_request[lang]
                        local p, buffer =
                            test_utils.setup_test(d.code, lang, d.row, d.col)
                        _99.fill_in_function()
                        assert.is_not_nil(p.request)
                        assert.is_false(p.request.request:is_cancelled())
                        _99.stop_all_requests()
                        test_utils.next_frame()
                        assert.is_true(p.request.request:is_cancelled())
                        eq(d.code, test_utils.lines(buffer))
                    end
                )

                it("handles error response gracefully", function()
                    local d = shared.simple_request[lang]
                    local p, buffer =
                        test_utils.setup_test(d.code, lang, d.row, d.col)
                    _99.fill_in_function()
                    p:resolve("failed", "API error")
                    test_utils.next_frame()
                    eq(d.code, test_utils.lines(buffer))
                end)
            end)

            -- Partial language coverage tests
            if shared.async_function[lang] then
                describe("async functions", function()
                    it("detects async function", function()
                        local d = shared.async_function[lang]
                        local p, buffer =
                            test_utils.setup_test(d.code, lang, d.row, d.col)
                        _99.fill_in_function()
                        assert.is_not_nil(p.request)
                        test_utils.assert_section_contains(
                            p.request.query,
                            "FunctionText",
                            d.check
                        )
                        p:resolve("success", d.resolve)
                        test_utils.next_frame()
                        eq(d.expect, test_utils.lines(buffer))
                    end)
                end)
            end

            if shared.enclosing_class[lang] then
                describe("class methods", function()
                    it("includes enclosing class in context", function()
                        local d = shared.enclosing_class[lang]
                        local p, buffer =
                            test_utils.setup_test(d.code, lang, d.row, d.col)
                        _99.fill_in_function()
                        assert.is_not_nil(p.request)
                        test_utils.assert_section_contains(
                            p.request.query,
                            "EnclosingContext",
                            d.ctx_check
                        )
                        test_utils.assert_section_contains(
                            p.request.query,
                            "FunctionText",
                            d.fn_check
                        )
                        p:resolve("success", d.resolve)
                        test_utils.next_frame()
                        eq(d.expect, test_utils.lines(buffer))
                    end)
                end)
            end

            if shared.closure[lang] then
                describe("closures", function()
                    it("detects closure in variable assignment", function()
                        local d = shared.closure[lang]
                        local p, buffer =
                            test_utils.setup_test(d.code, lang, d.row, d.col)
                        _99.fill_in_function()
                        assert.is_not_nil(p.request)
                        test_utils.assert_section_contains(
                            p.request.query,
                            "FunctionText",
                            d.check
                        )
                        p:resolve("success", d.resolve)
                        test_utils.next_frame()
                        eq(d.expect, test_utils.lines(buffer))
                    end)
                end)
            end
        end)
    end
end)
