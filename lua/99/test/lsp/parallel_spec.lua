-- luacheck: globals describe it assert before_each
local parallel = require("99.lsp.parallel")
local eq = assert.are.same

describe("parallel", function()
    describe("create_collector", function()
        it("should call callback immediately for count 0", function(done)
            local add_result, is_done = parallel.create_collector(0, function(results)
                eq({}, results)
                assert.is_true(is_done())
                done()
            end)
            assert.is_function(add_result)
            assert.is_function(is_done)
        end)

        it("should collect results in order", function(done)
            local add_result, is_done = parallel.create_collector(3, function(results)
                eq("first", results[1])
                eq("second", results[2])
                eq("third", results[3])
                assert.is_true(is_done())
                done()
            end)

            add_result(3, "third", nil)
            assert.is_false(is_done())
            add_result(1, "first", nil)
            assert.is_false(is_done())
            add_result(2, "second", nil)
        end)

        it("should ignore results after completion", function(done)
            local call_count = 0
            local add_result = parallel.create_collector(2, function(results)
                call_count = call_count + 1
                eq("a", results[1])
                eq("b", results[2])
            end)

            add_result(1, "a", nil)
            add_result(2, "b", nil)
            add_result(1, "changed", nil)
            add_result(3, "extra", nil)

            vim.defer_fn(function()
                eq(1, call_count)
                done()
            end, 10)
        end)
    end)

    describe("parallel_map", function()
        it("should process empty items", function(done)
            parallel.parallel_map({}, function() end, function(results)
                eq({}, results)
                done()
            end)
        end)

        it("should process nil items", function(done)
            parallel.parallel_map(nil, function() end, function(results)
                eq({}, results)
                done()
            end)
        end)

        it("should map items in parallel", function(done)
            local items = { "a", "b", "c" }
            local order = {}

            parallel.parallel_map(items, function(item, index, item_done)
                table.insert(order, index)
                item_done(item .. "_processed", nil)
            end, function(results)
                eq("a_processed", results[1])
                eq("b_processed", results[2])
                eq("c_processed", results[3])
                done()
            end)
        end)

        it("should return controller with cancel function", function()
            local controller = parallel.parallel_map({ 1, 2 }, function(_, _, item_done)
                vim.defer_fn(function()
                    item_done("result", nil)
                end, 100)
            end, function() end)

            assert.is_not_nil(controller)
            assert.is_function(controller.cancel)
            assert.is_function(controller.is_cancelled)
            assert.is_false(controller.is_cancelled())
            controller.cancel()
            assert.is_true(controller.is_cancelled())
        end)

        it("should stop processing after cancel", function(done)
            local processed = {}

            local controller = parallel.parallel_map({ 1, 2, 3, 4 }, function(item, _, item_done)
                if item == 2 then
                    controller.cancel()
                end
                table.insert(processed, item)
                item_done(item, nil)
            end, function() end)

            vim.defer_fn(function()
                assert.is_true(#processed >= 2)
                done()
            end, 50)
        end)
    end)

    describe("parallel_map_with_timeout", function()
        it("should complete before timeout", function(done)
            local items = { 1, 2, 3 }

            parallel.parallel_map_with_timeout(
                items,
                function(item, _, item_done)
                    item_done(item * 2, nil)
                end,
                1000,
                function(results, timed_out)
                    assert.is_false(timed_out)
                    eq(2, results[1])
                    eq(4, results[2])
                    eq(6, results[3])
                    done()
                end
            )
        end)

        it("should timeout on slow operations", function(done)
            parallel.parallel_map_with_timeout(
                { 1 },
                function(_, _, item_done)
                    vim.defer_fn(function()
                        item_done("result", nil)
                    end, 500)
                end,
                50,
                function(results, timed_out)
                    assert.is_true(timed_out)
                    eq({}, results)
                    done()
                end
            )
        end)
    end)

    describe("cancel_all", function()
        it("should cancel multiple controllers", function()
            local controllers = {}
            for i = 1, 3 do
                controllers[i] = parallel.parallel_map({ i }, function(_, _, item_done)
                    vim.defer_fn(function()
                        item_done("done", nil)
                    end, 100)
                end, function() end)
            end

            parallel.cancel_all(controllers)

            for _, controller in ipairs(controllers) do
                assert.is_true(controller.is_cancelled())
            end
        end)

        it("should handle nil controllers", function()
            parallel.cancel_all({ nil, nil })
        end)

        it("should handle empty array", function()
            parallel.cancel_all({})
        end)
    end)

    describe("wait_all", function()
        it("should wait for all operations", function(done)
            local operations = {
                function(op_done)
                    vim.defer_fn(function()
                        op_done("first")
                    end, 10)
                end,
                function(op_done)
                    op_done("second")
                end,
                function(op_done)
                    vim.defer_fn(function()
                        op_done("third")
                    end, 5)
                end,
            }

            parallel.wait_all(operations, function(results)
                eq("first", results[1])
                eq("second", results[2])
                eq("third", results[3])
                done()
            end)
        end)

        it("should handle empty operations", function(done)
            parallel.wait_all({}, function(results)
                eq({}, results)
                done()
            end)
        end)

        it("should handle nil operations", function(done)
            parallel.wait_all(nil, function(results)
                eq({}, results)
                done()
            end)
        end)
    end)

    describe("race", function()
        it("should return first result", function(done)
            local operations = {
                function(op_done)
                    vim.defer_fn(function()
                        op_done("slow")
                    end, 50)
                end,
                function(op_done)
                    op_done("fast")
                end,
            }

            parallel.race(operations, function(result, index)
                eq("fast", result)
                eq(2, index)
                done()
            end)
        end)

        it("should handle empty operations", function(done)
            parallel.race({}, function(result, index)
                assert.is_nil(result)
                eq(0, index)
                done()
            end)
        end)

        it("should handle nil operations", function(done)
            parallel.race(nil, function(result, index)
                assert.is_nil(result)
                eq(0, index)
                done()
            end)
        end)

        it("should only call callback once", function(done)
            local call_count = 0
            local operations = {
                function(op_done)
                    op_done("first")
                end,
                function(op_done)
                    op_done("second")
                end,
            }

            parallel.race(operations, function(_, _)
                call_count = call_count + 1
            end)

            vim.defer_fn(function()
                eq(1, call_count)
                done()
            end, 20)
        end)
    end)
end)
