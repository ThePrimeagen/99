--- @alias _99.Request.State "ready" | "calling-model" | "parsing-result" | "updating-file" | "cancelled"
--- @alias _99.Request.ResponseState "failed" | "success" | "cancelled"

--- @class _99.ProviderObserver
--- @field on_stdout fun(line: string): nil
--- @field on_stderr fun(line: string): nil
--- @field on_complete fun(status: _99.Request.ResponseState, res: string): nil

--- @class _99.Provider
--- @field make_request fun(self: _99.Provider, query: string, request: _99.Request, observer: _99.ProviderObserver)

local DevNullObserver = {
    name = "DevNullObserver",
    on_stdout = function() end,
    on_stderr = function() end,
    on_complete = function() end,
}

local OpenCodeProvider = {}

--- @param fn fun(...: any): nil
--- @return fun(...: any): nil
local function once(fn)
    local called = false
    return function(...)
        if called then
            return
        end
        called = true
        fn(...)
    end
end

--- @param query string
---@param request _99.Request
---@param observer _99.ProviderObserver?
function OpenCodeProvider:make_request(query, request, observer)
    _ = self
    local logger = request.logger:set_area("OpenCodeProvider")
    logger:debug("make_request", "tmp_file", request.context.tmp_file)

    observer = observer or DevNullObserver
    --- @param status _99.Request.ResponseState
    ---@param text string
    local once_complete = once(function(status, text)
        observer.on_complete(status, text)
    end)

    local command = { "opencode", "run", "-m", request.context.model, query }
    logger:debug("make_request", "command", command)
    local proc = vim.system(
        command,
        {
            text = true,
            stdout = vim.schedule_wrap(function(err, data)
                logger:debug("stdout", "data", data)
                if request:is_cancelled() then
                    once_complete("cancelled", "")
                    return
                end
                if err and err ~= "" then
                    logger:debug("stdout#error", "err", err)
                end
                if not err then
                    observer.on_stdout(data)
                end
            end),
            stderr = vim.schedule_wrap(function(err, data)
                logger:debug("stderr", "data", data)
                if request:is_cancelled() then
                    once_complete("cancelled", "")
                    return
                end
                if err and err ~= "" then
                    logger:debug("stderr#error", "err", err)
                end
                if not err then
                    observer.on_stderr(data)
                end
            end),
        },
        vim.schedule_wrap(function(obj)
            if request:is_cancelled() then
                once_complete("cancelled", "")
                logger:debug("on_complete: request has been cancelled")
                return
            end
            if obj.code ~= 0 then
                local str = string.format(
                    "process exit code: %d\n%s",
                    obj.code,
                    vim.inspect(obj)
                )
                once_complete("failed", str)
                logger:fatal(
                    "opencode make_query failed",
                    "obj from results",
                    obj
                )
            end
            vim.schedule(function()
                local ok, res = OpenCodeProvider._retrieve_response(request)
                if ok then
                    once_complete("success", res)
                else
                    once_complete(
                        "failed",
                        "unable to retrieve response from llm"
                    )
                end
            end)
        end)
    )

    request:_set_process(proc)
end

--- @param request _99.Request
function OpenCodeProvider._retrieve_response(request)
    local logger = request.logger:set_area("OpenCodeProvider")
    local tmp = request.context.tmp_file
    local success, result = pcall(function()
        return vim.fn.readfile(tmp)
    end)

    if not success then
        logger:error(
            "retrieve_results: failed to read file",
            "tmp_name",
            tmp,
            "error",
            result
        )
        return false, ""
    end

    local str = table.concat(result, "\n")
    logger:debug("retrieve_results", "results", str)

    return true, str
end

--- @class _99.Request.Opts
--- @field model string
--- @field tmp_file string
--- @field provider _99.Provider?
--- @field xid number

--- @class _99.Request.Config
--- @field model string
--- @field tmp_file string
--- @field provider _99.Provider
--- @field xid number

--- @class _99.Request
--- @field context _99.RequestContext
--- @field state _99.Request.State
--- @field provider _99.Provider
--- @field logger _99.Logger
--- @field _content string[]
--- @field _proc vim.SystemObj?

local Request = {}
Request.__index = Request

--- @param context _99.RequestContext
--- @return _99.Request
function Request.new(context)
    local provider = context._99.provider_override or OpenCodeProvider
    return setmetatable({
        context = context,
        provider = provider,
        state = "ready",
        logger = context.logger:set_area("Request"),
        _content = {},
        _proc = nil,
    }, Request)
end

--- @param proc vim.SystemObj?
function Request:_set_process(proc)
    self._proc = proc
end

function Request:cancel()
    self.logger:debug("cancel")
    self.state = "cancelled"
    if self._proc and self._proc.pid then
        pcall(function()
            local sigterm = (
                vim.uv
                and vim.uv.constants
                and vim.uv.constants.SIGTERM
            ) or 15
            self._proc:kill(sigterm)
        end)
    end
end

function Request:is_cancelled()
    return self.state == "cancelled"
end

--- @param content string
--- @return self
function Request:add_prompt_content(content)
    table.insert(self._content, content)
    return self
end

--- @param observer _99.ProviderObserver?
function Request:start(observer)
    self.context:finalize()
    for _, content in ipairs(self.context.ai_context) do
        self:add_prompt_content(content)
    end

    local query = table.concat(self._content, "\n")
    observer = observer or DevNullObserver

    self.logger:debug("start", "query", query)
    self.provider:make_request(query, self, observer)
end

return Request
