--- @class _99.Providers.Observer
--- @field on_stdout fun(line: string): nil
--- @field on_stderr fun(line: string): nil
--- @field on_complete fun(status: _99.Request.ResponseState, res: string): nil

--- @type _99.Providers.Observer
local DevNullObserver = {
  name = "DevNullObserver",
  on_stdout = function() end,
  on_stderr = function() end,
  on_complete = function() end,
}

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

--- @class _99.Providers.BaseProvider
--- @field _build_command fun(self: _99.Providers.BaseProvider, query: string, request: _99.Request): string[]
--- @field _get_provider_name fun(self: _99.Providers.BaseProvider): string
local BaseProvider = {}

--- @param callback fun(models: string[]|nil, err: string|nil): nil
function BaseProvider.fetch_models(callback)
  callback(nil, "This provider does not support listing models")
end

--- @param request _99.Request
function BaseProvider:_retrieve_response(request)
  local logger = request.logger:set_area(self:_get_provider_name())
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

--- @param query string
--- @param request _99.Request
--- @param observer _99.Providers.Observer?
function BaseProvider:make_request(query, request, observer)
  local logger = request.logger:set_area(self:_get_provider_name())
  logger:debug("make_request", "tmp_file", request.context.tmp_file)

  observer = observer or DevNullObserver
  local once_complete = once(function(status, text)
    observer.on_complete(status, text)
  end)

  local command = self:_build_command(query, request)
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
        if not err and data then
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
        local str =
          string.format("process exit code: %d\n%s", obj.code, vim.inspect(obj))
        once_complete("failed", str)
        logger:fatal(
          self:_get_provider_name() .. " make_query failed",
          "obj from results",
          obj
        )
      else
        vim.schedule(function()
          local ok, res = self:_retrieve_response(request)
          if ok then
            once_complete("success", res)
          else
            once_complete(
              "failed",
              "unable to retrieve response from temp file"
            )
          end
        end)
      end
    end)
  )

  request:_set_process(proc)
end

--- @class OpenCodeProvider : _99.Providers.BaseProvider
local OpenCodeProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param request _99.Request
--- @return string[]
function OpenCodeProvider._build_command(_, query, request)
  return {
    "opencode",
    "run",
    "--agent",
    "build",
    "-m",
    request.context.model,
    query,
  }
end

--- @return string
function OpenCodeProvider._get_provider_name()
  return "OpenCodeProvider"
end

--- @return string
function OpenCodeProvider._get_default_model()
  return "opencode/claude-sonnet-4-5"
end

function OpenCodeProvider.fetch_models(callback)
  vim.system({ "opencode", "models" }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        callback(nil, "Failed to fetch models from opencode")
        return
      end
      local models = vim.split(obj.stdout, "\n", { trimempty = true })
      callback(models, nil)
    end)
  end)
end

--- @class ClaudeCodeProvider : _99.Providers.BaseProvider
local ClaudeCodeProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param request _99.Request
--- @return string[]
function ClaudeCodeProvider._build_command(_, query, request)
  return {
    "claude",
    "--dangerously-skip-permissions",
    "--model",
    request.context.model,
    "--print",
    query,
  }
end

--- @return string
function ClaudeCodeProvider._get_provider_name()
  return "ClaudeCodeProvider"
end

--- @return string
function ClaudeCodeProvider._get_default_model()
  return "claude-sonnet-4-5"
end

-- TODO: the claude CLI has no way to list available models.
-- We could use the Anthropic API (https://docs.anthropic.com/en/api/models)
-- but that requires the user to have an ANTHROPIC_API_KEY set which isn't ideal.
-- Until Anthropic adds a CLI command for this, we have to hardcode the list here.
-- See https://github.com/anthropics/claude-code/issues/12612
function ClaudeCodeProvider.fetch_models(callback)
  callback({
    "claude-opus-4-6",
    "claude-sonnet-4-5",
    "claude-haiku-4-5",
    "claude-opus-4-5",
    "claude-opus-4-1",
    "claude-sonnet-4-0",
    "claude-opus-4-0",
    "claude-3-7-sonnet-latest",
  }, nil)
end

--- @class CursorAgentProvider : _99.Providers.BaseProvider
local CursorAgentProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param request _99.Request
--- @return string[]
function CursorAgentProvider._build_command(_, query, request)
  return { "cursor-agent", "--model", request.context.model, "--print", query }
end

--- @return string
function CursorAgentProvider._get_provider_name()
  return "CursorAgentProvider"
end

--- @return string
function CursorAgentProvider._get_default_model()
  return "sonnet-4.5"
end

function CursorAgentProvider.fetch_models(callback)
  vim.system({ "cursor-agent", "models" }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        callback(nil, "Failed to fetch models from cursor-agent")
        return
      end
      local models = {}
      for _, line in ipairs(vim.split(obj.stdout, "\n", { trimempty = true })) do
        -- `cursor-agent models` outputs lines like "model-id - description",
        -- so we grab everything before the first " - " separator
        local id = line:match("^(%S+)%s+%-")
        if id then
          table.insert(models, id)
        end
      end
      callback(models, nil)
    end)
  end)
end

--- @class KiroProvider : _99.Providers.BaseProvider
local KiroProvider = setmetatable({}, { __index = BaseProvider })

--- @param query string
--- @param request _99.Request
--- @return string[]
function KiroProvider._build_command(_, query, request)
  return {
    "kiro-cli",
    "chat",
    "--no-interactive",
    "--model",
    request.context.model,
    "--trust-all-tools",
    query,
  }
end

--- @return string
function KiroProvider._get_provider_name()
  return "KiroProvider"
end

--- @return string
function KiroProvider._get_default_model()
  return "claude-sonnet-4.5"
end

return {
  OpenCodeProvider = OpenCodeProvider,
  ClaudeCodeProvider = ClaudeCodeProvider,
  CursorAgentProvider = CursorAgentProvider,
  KiroProvider = KiroProvider,
}
