--- ACP session lifecycle management
local Message = require("99.acp.message")

--- @class ACPSession
--- @field session_id string ACP session identifier (nil until session/new responds)
--- @field request _99.Request Request object
--- @field observer _99.ProviderObserver Callbacks for this session
--- @field state "creating" | "active" | "completed" | "cancelled"
--- @field process any ACPProcess instance
--- @field logger _99.Logger
--- @field timeout_timer number|nil Timer for request timeout
--- @field _pending_updates table
---   Buffer for session/update notifications that arrive while state is "creating".
---   Race condition: OpenCode may stream updates before we process the session/new
---   response (which provides the session_id). These buffered updates are replayed
---   via _replay_pending_updates() once the session transitions to "active".
local ACPSession = {}
ACPSession.__index = ACPSession

--- Create new ACP session
--- @param process any ACPProcess
--- @param query string User prompt
--- @param request _99.Request Context and metadata
--- @param observer _99.ProviderObserver
--- @param transport any ACPTransport for registering response handlers
--- @param on_session_registered fun(session_id: string)|nil Optional callback when session gets its ID
--- @return ACPSession
function ACPSession.new(
  process,
  query,
  request,
  observer,
  transport,
  on_session_registered
)
  local self = setmetatable({
    session_id = nil,
    request = request,
    observer = observer,
    state = "creating",
    process = process,
    transport = transport,
    logger = request.logger:set_area("ACPSession"),
    timeout_timer = nil,
    query = query,
    on_session_registered = on_session_registered,
    response_chunks = {},
    last_tool_write_content = nil,
    _pending_updates = {},
  }, ACPSession)

  self.logger:debug("Creating session")
  self:_setup_timeout()

  local cwd = vim.fn.getcwd()
  local model = request.context.model
  local new_msg = Message.session_new_request(cwd, model)

  self.logger:debug("Creating session with model", "model", model)

  local session_new_req_id =
    string.format("session_new_%d", request.context.xid)

  local session_new_observer = {
    on_stdout = function() end,
    on_stderr = function() end,
    on_complete = function(status, response_data)
      if status == "failed" then
        self.logger:error("session/new failed", "error", response_data)
        self:_clear_timeout()
        self.observer.on_complete(
          "failed",
          "Failed to create session: " .. tostring(response_data)
        )
        return
      end
      self:_on_session_created(response_data)
    end,
  }

  transport:send(session_new_req_id, new_msg, session_new_observer)

  return self
end

--- Update type constants
local UpdateType = {
  AGENT_MESSAGE_CHUNK = "agent_message_chunk",
  AGENT_THOUGHT_CHUNK = "agent_thought_chunk",
  USER_MESSAGE_CHUNK = "user_message_chunk",
  TOOL_CALL = "tool_call",
  TOOL_CALL_UPDATE = "tool_call_update",
  PLAN = "plan",
  AVAILABLE_COMMANDS = "available_commands_update",
  CURRENT_MODE = "current_mode_update",
  ERROR = "error",
}

--- Handle agent_message_chunk update
--- @param self ACPSession
--- @param update table
local function handle_agent_message_chunk(self, update)
  local content = update.content
  if content and content.type == "text" and content.text then
    table.insert(self.response_chunks, content.text)
    vim.schedule(function()
      self.observer.on_stdout(content.text)
    end)
  end
end

--- Handle agent_thought_chunk update
--- @param self ACPSession
--- @param update table
local function handle_agent_thought_chunk(self, update)
  local content = update.content
  if content and content.type == "text" and content.text then
    self.logger:debug("Agent thought", "text", content.text)
  end
end

--- Handle tool_call update
--- @param self ACPSession
--- @param update table
local function handle_tool_call(self, update)
  self.logger:debug(
    "Tool call",
    "toolCallId",
    update.toolCallId,
    "title",
    update.title
  )
end

--- Try to capture content from rawInput if it matches our tmp_file
--- @param self ACPSession
--- @param update table
local function try_capture_from_raw_input(self, update)
  local raw_input = update.rawInput
  if not raw_input then
    return
  end

  local target_path = raw_input.filePath or raw_input.path
  local content = raw_input.content

  self.logger:debug(
    "Tool write details",
    "target_path",
    target_path,
    "expected_path",
    self.request.context.tmp_file,
    "has_content",
    content ~= nil
  )

  if content and target_path == self.request.context.tmp_file then
    self.last_tool_write_content = content
    self.logger:debug(
      "Captured tool write content from rawInput",
      "content_length",
      #content
    )
  end
end

--- Try to capture content from diff in content array
--- @param self ACPSession
--- @param update table
local function try_capture_from_content_array(self, update)
  if not update.content then
    return
  end

  for _, content_item in ipairs(update.content) do
    if content_item.type == "content" and content_item.content then
      local inner = content_item.content
      if inner.type == "text" and inner.text then
        self.logger:debug("Tool content text", "text_length", #inner.text)
      end
    elseif content_item.type == "diff" then
      self.logger:debug(
        "Tool diff",
        "path",
        content_item.path,
        "has_newText",
        content_item.newText ~= nil
      )
      if
        content_item.path == self.request.context.tmp_file
        and content_item.newText
      then
        self.last_tool_write_content = content_item.newText
        self.logger:debug(
          "Captured tool write content from diff",
          "content_length",
          #content_item.newText
        )
      end
    end
  end
end

--- Handle tool_call_update update
--- @param self ACPSession
--- @param update table
local function handle_tool_call_update(self, update)
  self.logger:debug(
    "Tool call update",
    "toolCallId",
    update.toolCallId,
    "status",
    update.status,
    "title",
    update.title,
    "kind",
    update.kind
  )

  if update.status ~= "in_progress" and update.status ~= "completed" then
    return
  end

  try_capture_from_raw_input(self, update)

  local raw_output = update.rawOutput
  if raw_output and raw_output.output then
    self.logger:debug(
      "Tool output received",
      "output_length",
      #raw_output.output
    )
  end

  try_capture_from_content_array(self, update)
end

--- Handle error update
--- @param self ACPSession
--- @param update table
local function handle_error(self, update)
  self.state = "completed"
  self:_clear_timeout()
  local error_msg = update.message or update.error or "ACP error"
  vim.schedule(function()
    self.observer.on_complete("failed", error_msg)
  end)
end

--- Dispatch table for update handlers
local update_handlers = {
  [UpdateType.AGENT_MESSAGE_CHUNK] = handle_agent_message_chunk,
  [UpdateType.AGENT_THOUGHT_CHUNK] = handle_agent_thought_chunk,
  [UpdateType.USER_MESSAGE_CHUNK] = function(self, update)
    self.logger:debug("User message chunk received", "content", update.content)
  end,
  [UpdateType.TOOL_CALL] = handle_tool_call,
  [UpdateType.TOOL_CALL_UPDATE] = handle_tool_call_update,
  [UpdateType.PLAN] = function(self, update)
    self.logger:debug("Plan update", "entries", update.entries)
  end,
  [UpdateType.AVAILABLE_COMMANDS] = function(self, update)
    self.logger:debug(
      "Available commands",
      "commands",
      update.availableCommands
    )
  end,
  [UpdateType.CURRENT_MODE] = function(self, update)
    self.logger:debug("Mode changed", "currentModeId", update.currentModeId)
  end,
  [UpdateType.ERROR] = handle_error,
}

--- Handle session/update notification
--- @param update table ACP update notification params (the 'update' field from params)
function ACPSession:handle_update(update)
  if self.state == "creating" then
    self.logger:debug(
      "Buffering update while creating",
      "sessionUpdate",
      update.sessionUpdate
    )
    table.insert(self._pending_updates, update)
    return
  end

  if self.state ~= "active" then
    return
  end

  local session_update = update.sessionUpdate

  if not session_update then
    self.logger:warn("Update missing sessionUpdate type", "update", update)
    return
  end

  local handler = update_handlers[session_update]
  if handler then
    handler(self, update)
  else
    self.logger:debug(
      "Unknown session update type",
      "sessionUpdate",
      session_update
    )
  end
end

--- Finalize session - get response and call on_complete
function ACPSession:_finalize()
  if self.state ~= "active" then
    return
  end

  self.state = "completed"
  self:_clear_timeout()

  self.logger:debug("Finalizing session", "session_id", self.session_id)

  vim.schedule(function()
    -- Response extraction priority:
    -- 1. last_tool_write_content: Captured from tool_call_update when OpenCode
    --    writes to our tmp_file (most reliable when available)
    -- 2. tmp_file: Read directly from disk (works when we missed the tool update)
    -- 3. response_chunks: Accumulated agent_message_chunks (fallback, rarely used)
    if self.last_tool_write_content then
      self.logger:debug(
        "Using captured tool write content",
        "session_id",
        self.session_id
      )
      self.observer.on_complete("success", self.last_tool_write_content)
      return
    end

    local tmp = self.request.context.tmp_file
    local success, result = pcall(function()
      return vim.fn.readfile(tmp)
    end)

    if success then
      local str = table.concat(result, "\n")
      self.logger:debug(
        "Response read from file",
        "session_id",
        self.session_id
      )
      self.observer.on_complete("success", str)
    elseif #self.response_chunks > 0 then
      local str = table.concat(self.response_chunks, "")
      self.logger:debug(
        "Using accumulated message chunks",
        "session_id",
        self.session_id
      )
      self.observer.on_complete("success", str)
    else
      self.logger:error(
        "Failed to read response file",
        "session_id",
        self.session_id,
        "tmp_file",
        tmp,
        "error",
        result
      )
      self.observer.on_complete(
        "failed",
        "Failed to read response file: " .. tostring(result)
      )
    end
  end)
end

--- Cancel this session
--- @param skip_on_complete boolean|nil If true, don't call observer.on_complete (for timeout handler)
function ACPSession:cancel(skip_on_complete)
  if self.state == "cancelled" or self.state == "completed" then
    return
  end

  self.logger:debug("Cancelling session", "session_id", self.session_id)
  self.state = "cancelled"
  self:_clear_timeout()

  -- Only send cancel notification if we have a session_id
  -- (may be nil if cancelled during "creating" state before session/new response)
  if self.session_id then
    local cancel_msg = Message.session_cancel_notification(self.session_id)
    self.process:_write_message(cancel_msg)
  end

  -- Notify observer to trigger cleanup (removes session from _active_sessions)
  -- Skip if caller will handle on_complete (e.g., timeout with custom message)
  if not skip_on_complete then
    vim.schedule(function()
      self.observer.on_complete("cancelled", "")
    end)
  end
end

--- Setup request timeout timer
function ACPSession:_setup_timeout()
  local self_ref = self
  self.timeout_timer = vim.fn.timer_start(120000, function()
    if self_ref.state == "creating" or self_ref.state == "active" then
      self_ref.logger:error("Request timeout")
      self_ref:cancel(true) -- skip_on_complete, we'll call it with "failed"
      vim.schedule(function()
        self_ref.observer.on_complete(
          "failed",
          "Request timeout after 2 minutes"
        )
      end)
    end
  end)
end

--- Clear timeout timer
function ACPSession:_clear_timeout()
  if self.timeout_timer then
    vim.fn.timer_stop(self.timeout_timer)
    self.timeout_timer = nil
  end
end

--- Send the prompt to the session
function ACPSession:_send_prompt()
  local prompt_msg = Message.session_prompt_request(
    self.session_id,
    self.query,
    self.request.context
  )
  local session_prompt_req_id =
    string.format("session_prompt_%d", self.request.context.xid)

  local self_ref = self
  local session_prompt_observer = {
    on_stdout = function() end,
    on_stderr = function() end,
    on_complete = function(prompt_status, prompt_response)
      if prompt_status == "failed" then
        self_ref.logger:error("session/prompt failed", "error", prompt_response)
        self_ref:_clear_timeout()
        self_ref.observer.on_complete(
          "failed",
          "Failed to send prompt: " .. tostring(prompt_response)
        )
      else
        self_ref.logger:debug(
          "Prompt completed",
          "session_id",
          self_ref.session_id,
          "stopReason",
          prompt_response
        )
        self_ref:_finalize()
      end
    end,
  }

  self.transport:send(
    session_prompt_req_id,
    prompt_msg,
    session_prompt_observer
  )
end

--- Switch model if server returned a different one, then send prompt
--- @param current_model string|nil The model the server is currently using
function ACPSession:_switch_model_if_needed(current_model)
  local model = self.request.context.model

  if not (model and current_model and model ~= current_model) then
    self:_send_prompt()
    return
  end

  self.logger:debug("Switching model", "from", current_model, "to", model)

  local set_model_msg =
    Message.session_set_model_request(self.session_id, model)
  local set_model_req_id =
    string.format("session_set_model_%d", self.request.context.xid)

  local self_ref = self
  local set_model_observer = {
    on_stdout = function() end,
    on_stderr = function() end,
    on_complete = function(set_status, set_response)
      if set_status == "failed" then
        self_ref.logger:warn(
          "Failed to switch model, using default",
          "error",
          set_response
        )
      else
        self_ref.logger:debug("Model switched successfully", "model", model)
      end
      self_ref:_send_prompt()
    end,
  }

  self.transport:send(set_model_req_id, set_model_msg, set_model_observer)
end

--- Handle successful session/new response
--- @param response_data table Response from session/new
function ACPSession:_on_session_created(response_data)
  local session_id = response_data.sessionId
  self.session_id = session_id
  self.state = "active"

  local current_model = response_data.models
    and response_data.models.currentModelId
  self.logger:debug(
    "Session created",
    "session_id",
    session_id,
    "currentModel",
    current_model
  )

  if self.on_session_registered then
    self.on_session_registered(session_id)
  end

  self:_replay_pending_updates()
  self:_switch_model_if_needed(current_model)
end

--- Replay any pending updates that were buffered during session creation
function ACPSession:_replay_pending_updates()
  if #self._pending_updates == 0 then
    return
  end

  self.logger:debug(
    "Replaying pending updates",
    "count",
    #self._pending_updates
  )

  local pending = self._pending_updates
  self._pending_updates = {}

  for _, update in ipairs(pending) do
    self:handle_update(update)
  end
end

return ACPSession
