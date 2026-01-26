--- @alias _99.Request.State "ready" | "calling-model" | "parsing-result" | "updating-file" | "cancelled"
--- @alias _99.Request.ResponseState "failed" | "success" | "cancelled"

local Providers = require("99.providers")

--- @class _99.Request.Opts
--- @field model string
--- @field tmp_file string
--- @field provider _99.Providers.BaseProvider?
--- @field xid number

--- @class _99.Request.Config
--- @field model string
--- @field tmp_file string
--- @field provider _99.Providers.BaseProvider
--- @field xid number

--- @class _99.Request
--- @field context _99.RequestContext
--- @field state _99.Request.State
--- @field provider _99.Providers.BaseProvider
--- @field logger _99.Logger
--- @field _content string[]
---@diagnostic disable-next-line: undefined-doc-name
--- @field _proc vim.SystemObj?
local Request = {}
Request.__index = Request

--- @param context _99.RequestContext
--- @return _99.Request
function Request.new(context)
  local provider = context._99.provider_override or Providers.OpenCodeProvider
  return setmetatable({
    context = context,
    provider = provider,
    state = "ready",
    logger = context.logger:set_area("Request"),
    _content = {},
    _proc = nil,
  }, Request)
end

---@diagnostic disable-next-line: undefined-doc-name
--- @param proc vim.SystemObj?
function Request:_set_process(proc)
  self._proc = proc
end

function Request:cancel()
  self.logger:debug("cancel")
  self.state = "cancelled"

  -- ACP: Cancel session
  if self._acp_session then
    self._acp_session:cancel()
  end

  -- CLI: Kill process
  ---@diagnostic disable-next-line: undefined-field
  if self._proc and self._proc.pid then
    pcall(function()
      local sigterm = (vim.uv and vim.uv.constants and vim.uv.constants.SIGTERM)
        or 15
      ---@diagnostic disable-next-line: undefined-field
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

--- @param observer _99.Providers.Observer?
function Request:start(observer)
  self.context._99:track_request(self.context)
  self.context:finalize()
  for _, content in ipairs(self.context.ai_context) do
    self:add_prompt_content(content)
  end

  local prompt = table.concat(self._content, "\n")
  self.context:save_prompt(prompt)
  self.logger:debug("start", "prompt", prompt)
  self.provider:make_request(prompt, self, observer)
end

return Request
