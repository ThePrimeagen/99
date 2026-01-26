--- ACP transport layer - handles NDJSON framing and message routing
--- @class ACPTransport
--- @field _proc vim.SystemObj
--- @field _pending_requests table<number, _99.ProviderObserver> Map of JSON-RPC id to observer
--- @field _request_id_map table<number, number> Map of internal request ID to JSON-RPC id
--- @field _next_rpc_id number Auto-incrementing JSON-RPC ID
--- @field _stdout_buffer string Buffer for incomplete lines
--- @field _logger _99.Logger
--- @field _notification_handler fun(notification: table)|nil
--- @field _process any Reference to ACPProcess for marking ready
local ACPTransport = {}
ACPTransport.__index = ACPTransport

--- Create new transport instance
--- @param proc vim.SystemObj
--- @param logger _99.Logger
--- @param process any ACPProcess instance (for marking ready)
--- @return ACPTransport
function ACPTransport.new(proc, logger, process)
  return setmetatable({
    _proc = proc,
    _pending_requests = {},
    _request_id_map = {},
    _next_rpc_id = 2,
    _stdout_buffer = "",
    _logger = logger:set_area("ACPTransport"),
    _notification_handler = nil,
    _process = process,
  }, ACPTransport)
end

--- Send JSON-RPC request
--- @param internal_request_id number 99.nvim's internal request tracking ID
--- @param message table JSON-RPC message structure
--- @param observer _99.ProviderObserver Callbacks for response
function ACPTransport:send(internal_request_id, message, observer)
  local rpc_id = self._next_rpc_id
  self._next_rpc_id = self._next_rpc_id + 1

  if not message.id then
    message.id = rpc_id
  end

  self._pending_requests[rpc_id] = observer
  self._request_id_map[internal_request_id] = rpc_id

  local encoded = vim.json.encode(message) .. "\n"
  self._logger:debug(
    "Sending request",
    "rpc_id",
    rpc_id,
    "method",
    message.method
  )

  pcall(function()
    self._proc:write(encoded)
  end)
end

--- Cancel a request
--- @param internal_request_id number
function ACPTransport:cancel_request(internal_request_id)
  local rpc_id = self._request_id_map[internal_request_id]
  if not rpc_id then
    return
  end

  self._pending_requests[rpc_id] = nil
  self._request_id_map[internal_request_id] = nil

  self._logger:debug("Request cancelled", "rpc_id", rpc_id)
end

--- Register notification handler
--- @param handler fun(notification: table)
function ACPTransport:on_notification(handler)
  self._notification_handler = handler
end

--- Handle stdout data - accumulates buffer and processes complete lines
--- @param data string Raw stdout data
function ACPTransport:_handle_stdout(data)
  self._stdout_buffer = self._stdout_buffer .. data

  while true do
    local newline_pos = self._stdout_buffer:find("\n")
    if not newline_pos then
      break
    end

    local line = self._stdout_buffer:sub(1, newline_pos - 1)
    self._stdout_buffer = self._stdout_buffer:sub(newline_pos + 1)

    if line ~= "" then
      self:_handle_message(line)
    end
  end
end

--- Parse and dispatch a complete JSON-RPC message
--- @param line string Complete JSON line
function ACPTransport:_handle_message(line)
  local ok, decoded = pcall(vim.json.decode, line)
  if not ok then
    self._logger:error(
      "Failed to decode JSON-RPC message",
      "line",
      line,
      "error",
      decoded
    )
    return
  end

  self._logger:debug(
    "Received message",
    "method",
    decoded.method,
    "rpc_id",
    decoded.id
  )

  if decoded.id and decoded.result ~= nil then
    self:_handle_response(decoded)
  elseif decoded.id and decoded.error then
    self:_handle_error(decoded)
  elseif decoded.method then
    self:_handle_notification(decoded)
  end
end

--- Handle JSON-RPC response
--- @param response table Response message with id and result
function ACPTransport:_handle_response(response)
  local rpc_id = response.id

  if rpc_id == 1 then
    self._logger:debug("Received initialize response")
    if self._process then
      self._process:_mark_ready()
    end
    return
  end

  local observer = self._pending_requests[rpc_id]
  if not observer then
    self._logger:warn("No observer for response", "rpc_id", rpc_id)
    return
  end

  self._pending_requests[rpc_id] = nil

  local result = response.result
  self._logger:debug("Response received", "rpc_id", rpc_id, "result", result)

  vim.schedule(function()
    if result and result.sessionId then
      observer.on_complete("success", result)
    elseif result and result.stopReason then
      observer.on_complete("success", result.stopReason)
    elseif result and type(result) == "string" then
      observer.on_complete("success", result)
    elseif result then
      observer.on_complete("success", vim.inspect(result))
    else
      observer.on_complete("success", "")
    end
  end)
end

--- Handle JSON-RPC error response
--- @param response table Error response with id and error
function ACPTransport:_handle_error(response)
  local rpc_id = response.id
  local error_msg = vim.inspect(response.error)

  self._logger:error(
    "Received error response",
    "rpc_id",
    rpc_id,
    "error",
    error_msg
  )

  if rpc_id == 1 and self._process then
    self._process._state = "crashed"
    return
  end

  local observer = self._pending_requests[rpc_id]
  if not observer then
    return
  end

  self._pending_requests[rpc_id] = nil

  vim.schedule(function()
    observer.on_complete("failed", "ACP error: " .. error_msg)
  end)
end

--- Handle JSON-RPC notification
--- @param notification table Notification with method and params
function ACPTransport:_handle_notification(notification)
  self._logger:debug("Received notification", "method", notification.method)

  if self._notification_handler then
    vim.schedule(function()
      self._notification_handler(notification)
    end)
  end
end

return ACPTransport
