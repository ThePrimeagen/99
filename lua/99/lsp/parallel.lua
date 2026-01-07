local M = {}

--- @class _99.Lsp.BatchResult
--- @field results table<number, any> Index -> result mapping
--- @field errors table<number, string> Index -> error mapping
--- @field completed number Number of completed requests
--- @field total number Total number of requests

--- @class _99.Lsp.ParallelController
--- @field cancel fun() Cancel all pending requests
--- @field is_cancelled fun(): boolean Check if cancelled

--- Create a result collector for parallel operations
--- @param count number Number of items to collect
--- @param on_complete fun(results: table<number, any>) Called when all complete
--- @return fun(index: number, result: any, err: string?) add_result Function to add results
--- @return fun(): boolean is_done Function to check if done
function M.create_collector(count, on_complete)
    if count == 0 then
        vim.schedule(function()
            on_complete({})
        end)
        return function() end, function() return true end
    end

    local results = {}
    local pending = count
    local completed = false

    local function add_result(index, result, _)
        if completed then
            return
        end
        results[index] = result
        pending = pending - 1
        if pending == 0 then
            completed = true
            on_complete(results)
        end
    end

    local function is_done()
        return completed
    end

    return add_result, is_done
end

--- Execute multiple async operations in parallel
--- @generic T
--- @param items T[] Items to process
--- @param executor fun(item: T, index: number, done: fun(result: any, err: string?)) Function to execute for each item
--- @param callback fun(results: table<number, any>) Called when all complete
--- @return _99.Lsp.ParallelController controller Control object for cancellation
function M.parallel_map(items, executor, callback)
    local cancelled = false

    local controller = {
        cancel = function()
            cancelled = true
        end,
        is_cancelled = function()
            return cancelled
        end,
    }

    if not items or #items == 0 then
        vim.schedule(function()
            callback({})
        end)
        return controller
    end

    local add_result, is_done = M.create_collector(#items, callback)

    for i, item in ipairs(items) do
        if cancelled then
            break
        end
        executor(item, i, function(result, err)
            if not cancelled and not is_done() then
                add_result(i, result, err)
            end
        end)
    end

    return controller
end

--- Execute multiple async operations with a timeout
--- @generic T
--- @param items T[] Items to process
--- @param executor fun(item: T, index: number, done: fun(result: any, err: string?)) Function to execute
--- @param timeout_ms number Timeout in milliseconds
--- @param callback fun(results: table<number, any>, timed_out: boolean) Called when complete or timeout
--- @return _99.Lsp.ParallelController controller Control object
function M.parallel_map_with_timeout(items, executor, timeout_ms, callback)
    local completed = false
    local timer = vim.uv.new_timer()
    local controller

    local function finish(results, timed_out)
        if completed then
            return
        end
        completed = true
        if timer then
            timer:stop()
            timer:close()
            timer = nil
        end
        callback(results, timed_out)
    end

    timer:start(timeout_ms, 0, vim.schedule_wrap(function()
        if not completed then
            if controller then
                controller.cancel()
            end
            finish({}, true)
        end
    end))

    controller = M.parallel_map(items, executor, function(results)
        finish(results, false)
    end)

    return controller
end

--- Batch LSP requests for the same method with different positions
--- @param bufnr number Buffer number
--- @param method string LSP method name (e.g., "textDocument/hover")
--- @param positions { line: number, character: number }[] Array of positions
--- @param callback fun(results: table<number, any>) Called with index -> result mapping
--- @return _99.Lsp.ParallelController controller
function M.batch_lsp_request(bufnr, method, positions, callback)
    return M.parallel_map(positions, function(position, _, done)
        local params = {
            textDocument = vim.lsp.util.make_text_document_params(bufnr),
            position = position,
        }

        vim.lsp.buf_request(bufnr, method, params, function(err, result, _, _)
            if err then
                done(nil, vim.inspect(err))
            else
                done(result, nil)
            end
        end)
    end, callback)
end

--- Batch LSP requests with timeout
--- @param bufnr number Buffer number
--- @param method string LSP method name
--- @param positions { line: number, character: number }[] Array of positions
--- @param timeout_ms number Timeout in milliseconds
--- @param callback fun(results: table<number, any>, timed_out: boolean)
--- @return _99.Lsp.ParallelController controller
function M.batch_lsp_request_with_timeout(bufnr, method, positions, timeout_ms, callback)
    return M.parallel_map_with_timeout(positions, function(position, _, done)
        local params = {
            textDocument = vim.lsp.util.make_text_document_params(bufnr),
            position = position,
        }

        vim.lsp.buf_request(bufnr, method, params, function(err, result, _, _)
            if err then
                done(nil, vim.inspect(err))
            else
                done(result, nil)
            end
        end)
    end, timeout_ms, callback)
end

--- Cancel multiple controllers at once
--- @param controllers _99.Lsp.ParallelController[] Controllers to cancel
function M.cancel_all(controllers)
    for _, controller in ipairs(controllers) do
        if controller and controller.cancel then
            controller.cancel()
        end
    end
end

--- Wait for all parallel operations to complete
--- Useful when you need to coordinate multiple independent batch operations
--- @param operations fun(done: fun(result: any))[] Array of async operations
--- @param callback fun(results: any[]) Called with all results
function M.wait_all(operations, callback)
    if not operations or #operations == 0 then
        callback({})
        return
    end

    local add_result = M.create_collector(#operations, callback)

    for i, operation in ipairs(operations) do
        operation(function(result)
            add_result(i, result, nil)
        end)
    end
end

--- Race multiple operations, returning the first to complete
--- @param operations fun(done: fun(result: any))[] Array of async operations
--- @param callback fun(result: any, index: number) Called with first result and its index
function M.race(operations, callback)
    if not operations or #operations == 0 then
        callback(nil, 0)
        return
    end

    local completed = false

    for i, operation in ipairs(operations) do
        operation(function(result)
            if not completed then
                completed = true
                callback(result, i)
            end
        end)
    end
end

return M
