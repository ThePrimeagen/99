--- ACP session lifecycle management
local Message = require("99.acp.message")

local _session_counter = 0

--- @class ACPSession
--- @field session_id string ACP session identifier
--- @field request _99.Request Request object
--- @field observer _99.ProviderObserver Callbacks for this session
--- @field state "creating" | "active" | "completed" | "cancelled"
--- @field process any ACPProcess instance
--- @field logger _99.Logger
--- @field timeout_timer number|nil Timer for request timeout
--- @field _pending_updates table Buffered updates received before session was active
local ACPSession = {}
ACPSession.__index = ACPSession

--- Generate unique session ID
--- @param request_xid number Request tracking ID
--- @return string
local function generate_session_id(request_xid)
  _session_counter = _session_counter + 1
  return string.format("99nvim-%d-%d", request_xid, _session_counter)
end

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

  self.timeout_timer = vim.fn.timer_start(120000, function()
    if self.state == "creating" or self.state == "active" then
      self.logger:error("Request timeout")
      self:cancel()
      vim.schedule(function()
        observer.on_complete("failed", "Request timeout after 2 minutes")
      end)
    end
  end)

  local cwd = vim.fn.getcwd()
  local model = request.context.model
  local new_msg = Message.session_new_request(cwd, model)

  self.logger:debug("Creating session with model", "model", model)

  local session_new_req_id =
    string.format("session_new_%d", request.context.xid)

  local function send_prompt(session_id)
    local prompt_msg =
      Message.session_prompt_request(session_id, query, request.context)
    local session_prompt_req_id =
      string.format("session_prompt_%d", request.context.xid)

    local session_prompt_observer = {
      on_stdout = function() end,
      on_stderr = function() end,
      on_complete = function(prompt_status, prompt_response)
        if prompt_status == "failed" then
          self.logger:error("session/prompt failed", "error", prompt_response)
          self:_clear_timeout()
          observer.on_complete(
            "failed",
            "Failed to send prompt: " .. tostring(prompt_response)
          )
        else
          self.logger:debug(
            "Prompt completed",
            "session_id",
            session_id,
            "stopReason",
            prompt_response
          )
          self:_finalize()
        end
      end,
    }

    transport:send(session_prompt_req_id, prompt_msg, session_prompt_observer)
  end

  local session_new_observer = {
    on_stdout = function() end,
    on_stderr = function() end,
    on_complete = function(status, response_data)
      if status == "failed" then
        self.logger:error("session/new failed", "error", response_data)
        self:_clear_timeout()
        observer.on_complete(
          "failed",
          "Failed to create session: " .. tostring(response_data)
        )
        return
      end

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

      if model and current_model and model ~= current_model then
        self.logger:debug("Switching model", "from", current_model, "to", model)

        local set_model_msg =
          Message.session_set_model_request(session_id, model)
        local set_model_req_id =
          string.format("session_set_model_%d", request.context.xid)

        local set_model_observer = {
          on_stdout = function() end,
          on_stderr = function() end,
          on_complete = function(set_status, set_response)
            if set_status == "failed" then
              self.logger:warn(
                "Failed to switch model, using default",
                "error",
                set_response
              )
            else
              self.logger:debug("Model switched successfully", "model", model)
            end
            send_prompt(session_id)
          end,
        }

        transport:send(set_model_req_id, set_model_msg, set_model_observer)
      else
        send_prompt(session_id)
      end
    end,
  }

  transport:send(session_new_req_id, new_msg, session_new_observer)

  return self
end

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

  if session_update == "agent_message_chunk" then
    local content = update.content
    if content and content.type == "text" and content.text then
      table.insert(self.response_chunks, content.text)
      vim.schedule(function()
        self.observer.on_stdout(content.text)
      end)
    end
  elseif session_update == "agent_thought_chunk" then
    local content = update.content
    if content and content.type == "text" and content.text then
      self.logger:debug("Agent thought", "text", content.text)
    end
  elseif session_update == "user_message_chunk" then
    self.logger:debug("User message chunk received", "content", update.content)
  elseif session_update == "tool_call" then
    self.logger:debug(
      "Tool call",
      "toolCallId",
      update.toolCallId,
      "title",
      update.title
    )
  elseif session_update == "tool_call_update" then
    self.logger:debug(
      "Tool call update",
      "toolCallId",
      update.toolCallId,
      "status",
      update.status
    )

    if update.status == "in_progress" or update.status == "completed" then
      local raw_input = update.rawInput
      if raw_input then
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

        if content then
          self.last_tool_write_content = content
          self.logger:debug(
            "Captured tool write content",
            "content_length",
            #content
          )
        end
      end
    end
  elseif session_update == "plan" then
    self.logger:debug("Plan update", "entries", update.entries)
  elseif session_update == "available_commands_update" then
    self.logger:debug(
      "Available commands",
      "commands",
      update.availableCommands
    )
  elseif session_update == "current_mode_update" then
    self.logger:debug("Mode changed", "currentModeId", update.currentModeId)
  elseif session_update == "error" then
    self.state = "completed"
    self:_clear_timeout()
    local error_msg = update.message or update.error or "ACP error"
    vim.schedule(function()
      self.observer.on_complete("failed", error_msg)
    end)
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
function ACPSession:cancel()
  if self.state == "cancelled" or self.state == "completed" then
    return
  end

  self.logger:debug("Cancelling session", "session_id", self.session_id)
  self.state = "cancelled"
  self:_clear_timeout()

  local cancel_msg = Message.session_cancel_notification(self.session_id)
  self.process:_write_message(cancel_msg)
end

--- Clear timeout timer
function ACPSession:_clear_timeout()
  if self.timeout_timer then
    vim.fn.timer_stop(self.timeout_timer)
    self.timeout_timer = nil
  end
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
