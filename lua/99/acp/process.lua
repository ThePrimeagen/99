--- ACP process lifecycle management
local Message = require("99.acp.message")

--- @class ACPProcess
--- @field _proc vim.SystemObj|nil
--- @field _transport any ACPTransport instance
--- @field _state "initializing" | "ready" | "crashed" | "terminated"
--- @field _logger _99.Logger
local ACPProcess = {}
ACPProcess.__index = ACPProcess

--- Start the opencode acp subprocess
--- @param logger _99.Logger
--- @param transport_factory fun(self: ACPProcess, proc: vim.SystemObj, logger: _99.Logger): any
--- @return ACPProcess?
function ACPProcess.start(logger, transport_factory)
  local self = setmetatable({
    _proc = nil,
    _transport = nil,
    _state = "initializing",
    _logger = logger:set_area("ACPProcess"),
  }, ACPProcess)

  self._logger:debug("Starting opencode acp process")

  local proc = vim.system({ "opencode", "acp" }, {
    stdin = true,
    text = true,
    stdout = function(err, data)
      if err then
        self._logger:error("stdout error", "err", err)
        self._state = "crashed"
        return
      end
      if data and self._transport then
        vim.schedule(function()
          self._transport:_handle_stdout(data)
        end)
      end
    end,
    stderr = function(err, data)
      if err then
        self._logger:error("stderr error", "err", err)
        return
      end
      if data then
        vim.schedule(function()
          self._logger:debug("stderr", "data", data)
        end)
      end
    end,
  })

  if not proc or not proc.pid then
    self._logger:error("Failed to start opencode acp process")
    return nil
  end

  self._proc = proc
  self._logger:debug("Process started", "pid", proc.pid)

  self._transport = transport_factory(self, proc, logger)

  local init_msg = Message.initialize_request()
  self:_write_message(init_msg)

  local success = vim.wait(5000, function()
    return self._state == "ready" or self._state == "crashed"
  end, 10)

  if not success or self._state ~= "ready" then
    self._logger:error(
      "ACP process failed to initialize",
      "state",
      self._state,
      "timed_out",
      not success
    )
    self:terminate()
    return nil
  end

  self._logger:debug("ACP process ready")
  return self
end

--- Mark process as ready (called by transport when initialize response received)
function ACPProcess:_mark_ready()
  self._state = "ready"
end

--- Write JSON-RPC message to stdin
--- @param message table JSON-RPC message
function ACPProcess:_write_message(message)
  if not self._proc or not self._proc.pid then
    self._logger:error("Cannot write to terminated process")
    return
  end

  local encoded = vim.json.encode(message) .. "\n"
  self._logger:debug(
    "Writing message",
    "method",
    message.method,
    "rpc_id",
    message.id
  )

  pcall(function()
    self._proc:write(encoded)
  end)
end

--- Send request via transport layer
--- @param request_id number Internal request ID
--- @param message table JSON-RPC message
--- @param observer _99.ProviderObserver
function ACPProcess:send_request(request_id, message, observer)
  if not self:is_healthy() then
    self._logger:error("Process not healthy, cannot send request")
    vim.schedule(function()
      observer.on_complete("failed", "ACP process not healthy")
    end)
    return
  end

  self._transport:send(request_id, message, observer)
end

--- Register notification handler
--- @param handler fun(notification: table)
function ACPProcess:on_notification(handler)
  self._transport:on_notification(handler)
end

--- Check if process is healthy
--- @return boolean
function ACPProcess:is_healthy()
  return self._state == "ready" and self._proc and self._proc.pid ~= nil
end

--- Terminate the ACP process gracefully
function ACPProcess:terminate()
  if self._state == "terminated" then
    return
  end

  self._logger:debug("Terminating ACP process")
  self._state = "terminated"

  if self._proc and self._proc.pid then
    pcall(function()
      local sigterm = (vim.uv and vim.uv.constants and vim.uv.constants.SIGTERM)
        or 15
      self._proc:kill(sigterm)
    end)
  end
end

return ACPProcess
