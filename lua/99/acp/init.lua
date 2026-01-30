--- ACPProvider - OpenCode Agent Client Protocol provider
---
--- Why ACP over CLI?
--- The CLI providers (opencode run, claude --print) hold locks that prevent
--- parallel execution. ACP allows multiple concurrent sessions on a single
--- long-lived process, enabling parallel multi-file refactors.
---
--- Concurrency Model:
--- - One shared ACPProcess spawns `opencode acp` and stays alive
--- - Multiple ACPSessions run concurrently (up to _max_concurrent_sessions)
--- - Sessions are tracked by temp_id until session/new returns the real session_id
--- - Notifications may arrive before session_id is known, requiring dual lookup
---
--- OpenCode Limitations (as of writing):
--- - No slash commands or session modes advertised
--- - No fs/read_text_file or fs/write_text_file support
--- - We use "write to tmp file" prompt pattern for response extraction
---
local ACPProcess = require("99.acp.process")
local ACPTransport = require("99.acp.transport")
local ACPSession = require("99.acp.session")

local BaseProvider = require("99.providers").BaseProvider

--- @class ACPProvider : BaseProvider
--- @field _shared_process ACPProcess? Singleton process instance shared across all sessions
--- @field _active_sessions table<string, ACPSession>
---   Map of session_id to ACPSession. Sessions are initially keyed by temp_id
---   (generated client-side) until session/new responds with the real session_id.
---   During high concurrency, session/update notifications may arrive before the
---   ID swap completes, so notification routing checks both map key and session.session_id.
--- @field _max_concurrent_sessions number Maximum concurrent sessions (enables parallel multi-file refactors)
--- @field _next_temp_id number Counter for generating unique temp IDs before real session_id is known
local ACPProvider = setmetatable({}, { __index = BaseProvider })

ACPProvider._shared_process = nil
ACPProvider._active_sessions = {}
ACPProvider._max_concurrent_sessions = 10
ACPProvider._next_temp_id = 0

--- Override: Start ACP process and create session
--- @param query string
--- @param request _99.Request
--- @param observer _99.ProviderObserver?
function ACPProvider:make_request(query, request, observer)
  local logger = request.logger:set_area("ACPProvider")

  if not observer then
    observer = {
      on_stdout = function() end,
      on_stderr = function() end,
      on_complete = function() end,
    }
  end

  local active_count = 0
  for _ in pairs(self._active_sessions) do
    active_count = active_count + 1
  end

  if active_count >= self._max_concurrent_sessions then
    logger:warn("Too many concurrent sessions", "active", active_count)
    vim.schedule(function()
      observer.on_complete(
        "failed",
        string.format(
          "Too many concurrent requests (%d). Please wait for some to complete.",
          active_count
        )
      )
    end)
    return
  end

  if not self._shared_process or not self._shared_process:is_healthy() then
    logger:debug("Starting ACP process")

    self._shared_process = ACPProcess.start(
      logger,
      function(process_self, proc, log)
        local transport = ACPTransport.new(proc, log, process_self)

        transport:on_notification(function(notification)
          if notification.method == "session/update" then
            local params = notification.params
            local session_id = params and params.sessionId
            if session_id then
              local session = self._active_sessions[session_id]

              -- Dual lookup: session may be keyed by real session_id (normal case)
              -- or still keyed by temp_id if session/new response hasn't arrived yet.
              -- This handles the race where updates stream before we know the real ID.
              if not session then
                for _, sess in pairs(self._active_sessions) do
                  if sess.session_id == session_id then
                    session = sess
                    break
                  end
                end
              end

              if session then
                session:handle_update(params.update)
              else
                logger:warn(
                  "No session found for update",
                  "session_id",
                  session_id
                )
              end
            end
          end
        end)

        return transport
      end
    )

    if not self._shared_process then
      logger:error("Failed to start ACP process")
      vim.schedule(function()
        observer.on_complete(
          "failed",
          "Failed to start ACP process. Is opencode installed and supports ACP?"
        )
      end)
      return
    end
  end

  local transport = self._shared_process._transport

  self._next_temp_id = self._next_temp_id + 1
  local temp_id =
    string.format("temp-%d-%d", request.context.xid, self._next_temp_id)

  local original_on_complete = observer.on_complete
  local wrapped_observer = {
    on_stdout = observer.on_stdout,
    on_stderr = observer.on_stderr,
    on_complete = function(status, response)
      if self._active_sessions[temp_id] then
        self._active_sessions[temp_id] = nil
      end
      local sess = request._acp_session
      if
        sess
        and sess.session_id
        and self._active_sessions[sess.session_id]
      then
        self._active_sessions[sess.session_id] = nil
      end
      original_on_complete(status, response)
    end,
  }

  local session = ACPSession.new(
    self._shared_process,
    query,
    request,
    wrapped_observer,
    transport,
    function(real_session_id)
      if self._active_sessions[temp_id] then
        self._active_sessions[real_session_id] = self._active_sessions[temp_id]
        self._active_sessions[temp_id] = nil
        logger:debug("Session registered", "session_id", real_session_id)
      end
    end
  )

  self._active_sessions[temp_id] = session
  session._temp_id = temp_id

  request._acp_session = session

  logger:debug("Session created", "temp_id", temp_id)
end

--- Get provider name
--- @return string
function ACPProvider._get_provider_name()
  return "ACPProvider"
end

--- Get default model
--- @return string
function ACPProvider._get_default_model()
  return "anthropic/claude-sonnet-4-5"
end

--- Shutdown ACP process (called on plugin exit)
function ACPProvider:shutdown()
  if self._shared_process then
    self._shared_process:terminate()
    self._shared_process = nil
  end
  self._active_sessions = {}
end

return ACPProvider
