-- luacheck: globals describe it assert before_each
-- luacheck: ignore 311 113
local parallel = require("99.lsp.parallel")
local eq = assert.are.same

describe("parallel", function()
    describe("create_collector", function()
        it("should call callback immediately for count 0", function()
            local called = false
            local collected_results
            local add_result, is_done = parallel.create_collector(
                0,
                function(results)
                    called = true
                    collected_results = results
                end
            )
            assert.is_function(add_result)
            assert.is_function(is_done)
            vim.wait(100, function()
                return called
            end)
            assert.is_true(called)
            eq({}, collected_results)
        end)

        it("should collect results in order", function()
            local called = false
            local collected_results
            local add_result, is_done = parallel.create_collector(
                3,
                function(results)
                    called = true
                    collected_results = results
                end
            )

            add_result(3, "third", nil)
            assert.is_false(is_done())
            add_result(1, "first", nil)
            assert.is_false(is_done())
            add_result(2, "second", nil)

            vim.wait(100, function()
                return called
            end)
            assert.is_true(called)
            eq("first", collected_results[1])
            eq("second", collected_results[2])
            eq("third", collected_results[3])
        end)

        it("should ignore results after completion", function()
            local call_count = 0
            local collected_results
            local add_result = parallel.create_collector(2, function(results)
                call_count = call_count + 1
                collected_results = results
            end)

            add_result(1, "a", nil)
            add_result(2, "b", nil)
            add_result(1, "changed", nil)
            add_result(3, "extra", nil)

            vim.wait(100, function()
                return call_count > 0
            end)
            eq(1, call_count)
            eq("a", collected_results[1])
            eq("b", collected_results[2])
        end)
    end)

    describe("parallel_map", function()
        it("should process empty items", function()
            local called = false
            local collected_results
            parallel.parallel_map({}, function() end, function(results)
                called = true
                collected_results = results
            end)
            vim.wait(100, function()
                return called
            end)
            assert.is_true(called)
            eq({}, collected_results)
        end)

        it("should process nil items", function()
            local called = false
            local collected_results
            parallel.parallel_map(nil, function() end, function(results)
                called = true
                collected_results = results
            end)
            vim.wait(100, function()
                return called
            end)
            assert.is_true(called)
            eq({}, collected_results)
        end)

        it("should map items in parallel", function()
            local items = { "a", "b", "c" }
            local called = false
            local collected_results

            parallel.parallel_map(items, function(item, _, item_done)
                item_done(item .. "_processed", nil)
            end, function(results)
                called = true
                collected_results = results
            end)

            vim.wait(100, function()
                return called
            end)
            assert.is_true(called)
            eq(3, #collected_results)
            eq("a_processed", collected_results[1])
            eq("b_processed", collected_results[2])
            eq("c_processed", collected_results[3])
        end)

        it("should return controller with cancel function", function()
            local controller = parallel.parallel_map(
                { 1, 2, 3 },
                function() end,
                function() end
            )
            assert.is_not_nil(controller)
            assert.is_function(controller.cancel)
            assert.is_function(controller.is_cancelled)
        end)

        it("should stop processing after cancel", function()
            local controller = parallel.parallel_map(
                { 1, 2, 3 },
                function(_, _, item_done)
                    vim.defer_fn(function()
                        item_done(nil, nil)
                    end, 1000)
                end,
                function() end
            )

            controller.cancel()
            assert.is_true(controller.is_cancelled())
        end)
    end)

    describe("parallel_map_with_timeout", function()
        it("should complete before timeout", function()
            local items = { 1, 2, 3 }
            local called = false
            local collected_results
            local timed_out_flag

            parallel.parallel_map_with_timeout(
                items,
                function(item, _, item_done)
                    item_done(item * 2, nil)
                end,
                5000,
                function(results, timed_out)
                    called = true
                    collected_results = results
                    timed_out_flag = timed_out
                end
            )

            vim.wait(200, function()
                return called
            end)
            assert.is_true(called)
            assert.is_false(timed_out_flag)
            eq({ 2, 4, 6 }, collected_results)
        end)
    end)

    describe("batch_lsp_request", function()
        it("should return controller", function()
            local controller = parallel.batch_lsp_request(
                0,
                "textDocument/hover",
                {},
                function() end
            )
            assert.is_not_nil(controller)
        end)
    end)

    describe("cancel_all", function()
        it("should cancel multiple controllers", function()
            local cancelled = { false, false }
            local controllers = {
                {
                    cancel = function()
                        cancelled[1] = true
                    end,
                },
                {
                    cancel = function()
                        cancelled[2] = true
                    end,
                },
            }

            parallel.cancel_all(controllers)
            assert.is_true(cancelled[1])
            assert.is_true(cancelled[2])
        end)

        it("should handle empty array", function()
            parallel.cancel_all({})
        end)

        it("should handle nil", function()
            parallel.cancel_all(nil)
        end)
    end)

    describe("wait_all", function()
        it("should call callback when all complete", function()
            local called = false
            local collected_results

            parallel.wait_all({
                function(done)
                    done("a")
                end,
                function(done)
                    done("b")
                end,
            }, function(results)
                called = true
                collected_results = results
            end)

            vim.wait(100, function()
                return called
            end)
            assert.is_true(called)
            eq(2, #collected_results)
        end)

        it("should handle empty operations", function()
            local called = false
            local collected_results

            parallel.wait_all({}, function(results)
                called = true
                collected_results = results
            end)

            vim.wait(100, function()
                return called
            end)
            assert.is_true(called)
            eq({}, collected_results)
        end)
    end)

    describe("race", function()
        it("should return first result", function()
            local called = false
            local race_result

            parallel.race({
                function(done)
                    done("first")
                end,
                function(done)
                    vim.defer_fn(function()
                        done("second")
                    end, 100)
                end,
            }, function(result)
                called = true
                race_result = result
            end)

            vim.wait(50, function()
                return called
            end)
            assert.is_true(called)
            eq("first", race_result)
        end)

        it("should handle empty operations", function()
            local called = false
            local race_result = "not_nil"

            parallel.race({}, function(result)
                called = true
                race_result = result
            end)

            vim.wait(100, function()
                return called
            end)
            assert.is_true(called)
            assert.is_nil(race_result)
        end)
    end)
end)
