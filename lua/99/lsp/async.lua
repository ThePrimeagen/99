local M = {}

--- @class _99.Lsp.AsyncError
--- @field message string Error message
--- @field traceback string? Stack traceback

--- Wait for a single async operation to complete
--- Must be called inside a coroutine created by async.run()
--- @generic T
--- @param fn fun(callback: fun(result: T, err: string?)) The async function
--- @return T? result The result from the callback
--- @return string? err Error message if any
function M.await(fn)
    local co = coroutine.running()
    assert(
        co,
        "async.await() must be called inside a coroutine created by async.run()"
    )

    fn(function(result, err)
        vim.schedule(function()
            coroutine.resume(co, result, err)
        end)
    end)

    return coroutine.yield()
end

--- Run an async function as a coroutine with error handling
--- @generic T
--- @param fn fun(): T The async function to run (can use await/wrap inside)
--- @param callback fun(result: T?, err: _99.Lsp.AsyncError?) Called when complete
function M.run(fn, callback)
    local co = coroutine.create(function()
        local ok, result_or_err = xpcall(fn, function(err)
            return {
                message = tostring(err),
                traceback = debug.traceback(nil, 2),
            }
        end)

        if ok then
            return result_or_err, nil
        else
            return nil, result_or_err
        end
    end)

    local function step(...)
        local ok, result_or_err, err = coroutine.resume(co, ...)

        if not ok then
            callback(nil, {
                message = tostring(result_or_err),
                traceback = debug.traceback(co),
            })
        elseif coroutine.status(co) == "dead" then
            callback(result_or_err, err)
        end
    end

    vim.schedule(step)
end

--- Run an async function with timeout protection
--- @generic T
--- @param fn fun(): T The async function to run
--- @param timeout_ms number Timeout in milliseconds
--- @param callback fun(result: T?, err: string?) Called when complete or timeout
function M.run_with_timeout(fn, timeout_ms, callback)
    local completed = false
    local timer = vim.uv.new_timer()

    timer:start(
        timeout_ms,
        0,
        vim.schedule_wrap(function()
            if not completed then
                completed = true
                timer:stop()
                timer:close()
                callback(nil, "timeout")
            end
        end)
    )

    M.run(fn, function(result, err)
        if not completed then
            completed = true
            timer:stop()
            timer:close()

            if err then
                if type(err) == "table" and err.message then
                    callback(nil, err.message)
                else
                    callback(nil, tostring(err))
                end
            else
                callback(result, nil)
            end
        end
    end)
end

--- Execute multiple async operations in parallel
--- Returns when ALL operations complete
--- Must be called inside a coroutine created by async.run()
--- @generic T, R
--- @param items T[] Items to process
--- @param executor fun(item: T): R?, string? Async function to execute for each item (using await inside)
--- @return table<number, R?> results Index -> result mapping
function M.parallel_map(items, executor)
    if not items or #items == 0 then
        return {}
    end

    local co = coroutine.running()
    assert(
        co,
        "async.parallel_map() must be called inside a coroutine created by async.run()"
    )

    local results = {}
    local errors = {}
    local pending = #items

    for i, item in ipairs(items) do
        M.run(function()
            return executor(item)
        end, function(result, err)
            results[i] = result
            if err then
                errors[i] = err
            end
            pending = pending - 1

            if pending == 0 then
                vim.schedule(function()
                    coroutine.resume(co, results, errors)
                end)
            end
        end)
    end

    local res, _ = coroutine.yield()
    return res
end

return M
