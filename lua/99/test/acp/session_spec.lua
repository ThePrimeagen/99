-- luacheck: globals describe it assert before_each
local eq = assert.are.same
local ACPSession = require("99.acp.session")
local Logger = require("99.logger.logger")
local test_utils = require("99.test.test_utils")

describe("acp/session", function()
  local mock_transport
  local mock_process
  local mock_request
  local mock_observer
  local sent_messages
  local observer_calls

  before_each(function()
    sent_messages = {}
    observer_calls = {
      on_stdout = {},
      on_stderr = {},
      on_complete = nil,
    }

    mock_transport = {
      send = function(_, req_id, message, observer)
        table.insert(sent_messages, {
          req_id = req_id,
          message = message,
          observer = observer,
        })
      end,
      send_notification = function(_, message)
        table.insert(sent_messages, {
          notification = true,
          message = message,
        })
      end,
    }

    mock_process = {
      _write_message = function(_, message)
        table.insert(sent_messages, {
          direct_write = true,
          message = message,
        })
      end,
    }

    mock_request = {
      context = {
        xid = 123,
        model = "test-model",
        ai_context = { "context1", "context2" },
        tmp_file = "/tmp/test-response.txt",
      },
      logger = Logger:set_id(1),
    }

    mock_observer = {
      on_stdout = function(data)
        table.insert(observer_calls.on_stdout, data)
      end,
      on_stderr = function(data)
        table.insert(observer_calls.on_stderr, data)
      end,
      on_complete = function(status, result)
        observer_calls.on_complete = { status = status, result = result }
      end,
    }
  end)

  -- Helper to create a session and simulate session/new response
  local function create_active_session(opts)
    opts = opts or {}
    local on_registered_calls = {}

    local session = ACPSession.new(
      mock_process,
      opts.query or "test query",
      mock_request,
      mock_observer,
      mock_transport,
      function(session_id)
        table.insert(on_registered_calls, session_id)
      end
    )

    if opts.skip_activation then
      return session, on_registered_calls
    end

    -- Simulate session/new response by calling the observer
    local session_new_sent = sent_messages[1]
    assert(session_new_sent, "session/new should have been sent")

    session_new_sent.observer.on_complete("success", {
      sessionId = opts.session_id or "real-session-123",
      models = { currentModelId = "test-model" },
    })
    test_utils.next_frame()

    return session, on_registered_calls
  end

  describe("state transitions", function()
    it("starts in creating state", function()
      local session, _ = create_active_session({ skip_activation = true })
      eq("creating", session.state)
    end)

    it("transitions to active when session_id received", function()
      local session, _ = create_active_session()
      eq("active", session.state)
      eq("real-session-123", session.session_id)
    end)

    it("calls on_session_registered with real session_id", function()
      local _, on_registered_calls = create_active_session({
        session_id = "my-session-id",
      })
      eq({ "my-session-id" }, on_registered_calls)
    end)

    it("transitions to cancelled on cancel()", function()
      local session, _ = create_active_session()
      eq("active", session.state)

      session:cancel()

      eq("cancelled", session.state)
    end)

    it("cancel sends session/cancel notification", function()
      local session, _ = create_active_session({ session_id = "cancel-test" })
      local msg_count_before = #sent_messages

      session:cancel()

      -- Find the cancel message
      local cancel_msg = nil
      for i = msg_count_before + 1, #sent_messages do
        local msg = sent_messages[i]
        if msg.message and msg.message.method == "session/cancel" then
          cancel_msg = msg.message
          break
        end
      end

      assert(cancel_msg, "session/cancel should have been sent")
      eq("cancel-test", cancel_msg.params.sessionId)
    end)

    it("cancel skips notification when session_id is nil", function()
      local session, _ = create_active_session({ skip_activation = true })
      eq("creating", session.state)
      eq(nil, session.session_id)

      local msg_count_before = #sent_messages

      session:cancel()

      eq("cancelled", session.state)

      -- Should NOT have sent a cancel message
      local cancel_msg = nil
      for i = msg_count_before + 1, #sent_messages do
        local msg = sent_messages[i]
        if msg.message and msg.message.method == "session/cancel" then
          cancel_msg = msg.message
          break
        end
      end

      eq(nil, cancel_msg)
    end)

    it("cancel calls observer.on_complete for cleanup", function()
      local session, _ = create_active_session()

      session:cancel()
      test_utils.next_frame()

      assert(observer_calls.on_complete, "on_complete should have been called")
      eq("cancelled", observer_calls.on_complete.status)
    end)

    it("cancel with skip_on_complete does not call observer", function()
      local session, _ = create_active_session()

      session:cancel(true) -- skip_on_complete = true
      test_utils.next_frame()

      eq(nil, observer_calls.on_complete)
    end)

    it("ignores duplicate cancel calls", function()
      local session, _ = create_active_session()
      local msg_count_before = #sent_messages

      session:cancel()
      session:cancel()
      session:cancel()

      -- Count cancel messages
      local cancel_count = 0
      for i = msg_count_before + 1, #sent_messages do
        local msg = sent_messages[i]
        if msg.message and msg.message.method == "session/cancel" then
          cancel_count = cancel_count + 1
        end
      end

      eq(1, cancel_count)
    end)
  end)

  describe("pending updates buffer", function()
    it("buffers updates while in creating state", function()
      local session, _ = create_active_session({ skip_activation = true })
      eq("creating", session.state)

      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "buffered text" },
      })

      eq(1, #session._pending_updates)
      eq(0, #observer_calls.on_stdout)
    end)

    it("replays pending updates when session becomes active", function()
      local session, _ = create_active_session({ skip_activation = true })

      -- Buffer some updates while creating
      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "chunk1" },
      })
      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "chunk2" },
      })

      eq(2, #session._pending_updates)
      eq(0, #observer_calls.on_stdout)

      -- Now activate the session
      local session_new_sent = sent_messages[1]
      session_new_sent.observer.on_complete("success", {
        sessionId = "real-session-123",
        models = { currentModelId = "test-model" },
      })
      test_utils.next_frame()

      -- Pending updates should have been replayed
      eq(0, #session._pending_updates)
      eq(2, #observer_calls.on_stdout)
      eq("chunk1", observer_calls.on_stdout[1])
      eq("chunk2", observer_calls.on_stdout[2])
    end)

    it("clears pending buffer after replay", function()
      local session, _ = create_active_session({ skip_activation = true })

      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "test" },
      })

      eq(1, #session._pending_updates)

      -- Activate
      local session_new_sent = sent_messages[1]
      session_new_sent.observer.on_complete("success", {
        sessionId = "real-session-123",
        models = { currentModelId = "test-model" },
      })
      test_utils.next_frame()

      eq(0, #session._pending_updates)
    end)
  end)

  describe("handle_update", function()
    it("forwards agent_message_chunk to observer.on_stdout", function()
      local session, _ = create_active_session()

      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "hello world" },
      })
      test_utils.next_frame()

      eq(1, #observer_calls.on_stdout)
      eq("hello world", observer_calls.on_stdout[1])
    end)

    it("accumulates text chunks in response_chunks", function()
      local session, _ = create_active_session()

      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "part1" },
      })
      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "part2" },
      })

      eq(2, #session.response_chunks)
      eq("part1", session.response_chunks[1])
      eq("part2", session.response_chunks[2])
    end)

    it("captures tool write content from rawInput", function()
      local session, _ = create_active_session()

      session:handle_update({
        sessionUpdate = "tool_call_update",
        toolCallId = "call-1",
        status = "in_progress",
        rawInput = {
          filePath = "/tmp/test-response.txt",
          content = "response from tool",
        },
      })

      eq("response from tool", session.last_tool_write_content)
    end)

    it("ignores rawInput for wrong path", function()
      local session, _ = create_active_session()

      session:handle_update({
        sessionUpdate = "tool_call_update",
        toolCallId = "call-1",
        status = "in_progress",
        rawInput = {
          filePath = "/some/other/file.txt",
          content = "wrong file content",
        },
      })

      eq(nil, session.last_tool_write_content)
    end)

    it("captures tool write content from diff", function()
      local session, _ = create_active_session()

      session:handle_update({
        sessionUpdate = "tool_call_update",
        toolCallId = "call-1",
        status = "completed",
        content = {
          {
            type = "diff",
            path = "/tmp/test-response.txt",
            newText = "diff content here",
          },
        },
      })

      eq("diff content here", session.last_tool_write_content)
    end)

    it("ignores diff for wrong path", function()
      local session, _ = create_active_session()

      session:handle_update({
        sessionUpdate = "tool_call_update",
        toolCallId = "call-1",
        status = "completed",
        content = {
          {
            type = "diff",
            path = "/some/other/file.txt",
            newText = "wrong file content",
          },
        },
      })

      eq(nil, session.last_tool_write_content)
    end)

    it("handles error update by completing with failed status", function()
      local session, _ = create_active_session()

      session:handle_update({
        sessionUpdate = "error",
        message = "Something went wrong",
      })
      test_utils.next_frame()

      eq("completed", session.state)
      eq("failed", observer_calls.on_complete.status)
      eq("Something went wrong", observer_calls.on_complete.result)
    end)

    it("ignores updates after completed state", function()
      local session, _ = create_active_session()
      session.state = "completed"

      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "should be ignored" },
      })
      test_utils.next_frame()

      eq(0, #observer_calls.on_stdout)
    end)

    it("ignores updates after cancelled state", function()
      local session, _ = create_active_session()
      session:cancel()

      session:handle_update({
        sessionUpdate = "agent_message_chunk",
        content = { type = "text", text = "should be ignored" },
      })
      test_utils.next_frame()

      eq(0, #observer_calls.on_stdout)
    end)
  end)

  describe("response extraction", function()
    it("prefers last_tool_write_content when available", function()
      local session, _ = create_active_session()
      session.last_tool_write_content = "tool write response"

      session:_finalize()
      test_utils.next_frame()

      eq("success", observer_calls.on_complete.status)
      eq("tool write response", observer_calls.on_complete.result)
    end)

    it("falls back to response_chunks when no tool content", function()
      local session, _ = create_active_session()
      session.response_chunks = { "chunk1", "chunk2", "chunk3" }
      -- No tool write content, no tmp file

      session:_finalize()
      test_utils.next_frame()

      eq("success", observer_calls.on_complete.status)
      eq("chunk1chunk2chunk3", observer_calls.on_complete.result)
    end)

    it("fails when no response sources available", function()
      local session, _ = create_active_session()
      -- No tool write content, no tmp file, no chunks

      session:_finalize()
      test_utils.next_frame()

      eq("failed", observer_calls.on_complete.status)
      assert(
        observer_calls.on_complete.result:find("Failed to read response"),
        "Should mention failed to read response"
      )
    end)

    it("sets state to completed after finalize", function()
      local session, _ = create_active_session()
      session.last_tool_write_content = "test"

      session:_finalize()
      test_utils.next_frame()

      eq("completed", session.state)
    end)

    it("only finalizes once", function()
      local session, _ = create_active_session()
      session.last_tool_write_content = "test"

      session:_finalize()
      test_utils.next_frame()

      local first_result = observer_calls.on_complete

      -- Try to finalize again
      observer_calls.on_complete = nil
      session:_finalize()
      test_utils.next_frame()

      -- Should not have called on_complete again
      eq(nil, observer_calls.on_complete)
      eq("test", first_result.result)
    end)
  end)

  describe("session creation flow", function()
    it("sends session/new on creation", function()
      create_active_session({ skip_activation = true })

      eq(1, #sent_messages)
      local msg = sent_messages[1].message
      eq("session/new", msg.method)
    end)

    it("sends session/prompt after session/new succeeds", function()
      create_active_session({ query = "my test query" })

      -- Should have session/new and session/prompt
      local prompt_msg = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/prompt" then
          prompt_msg = sent.message
          break
        end
      end

      assert(prompt_msg, "session/prompt should have been sent")
      eq("real-session-123", prompt_msg.params.sessionId)
    end)

    it("includes ai_context in prompt content blocks", function()
      create_active_session()

      local prompt_msg = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/prompt" then
          prompt_msg = sent.message
          break
        end
      end

      assert(prompt_msg, "session/prompt should have been sent")
      local prompt_blocks = prompt_msg.params.prompt

      -- First two blocks should be from ai_context
      eq("text", prompt_blocks[1].type)
      eq("context1", prompt_blocks[1].text)
      eq("text", prompt_blocks[2].type)
      eq("context2", prompt_blocks[2].text)
    end)

    it("includes tmp_file instruction in prompt", function()
      create_active_session()

      local prompt_msg = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/prompt" then
          prompt_msg = sent.message
          break
        end
      end

      local last_block = prompt_msg.params.prompt[#prompt_msg.params.prompt]
      assert(
        last_block.text:find("/tmp/test%-response%.txt"),
        "Should include tmp_file path in prompt"
      )
    end)

    it("fails when session/new fails", function()
      local session, _ = create_active_session({ skip_activation = true })

      local session_new_sent = sent_messages[1]
      session_new_sent.observer.on_complete("failed", "Connection refused")
      test_utils.next_frame()

      eq("failed", observer_calls.on_complete.status)
      assert(
        observer_calls.on_complete.result:find("Failed to create session"),
        "Should mention failed to create session"
      )
    end)

    it("switches model when server returns different model", function()
      local session, _ = create_active_session({ skip_activation = true })

      -- Server returns a different model than requested
      local session_new_sent = sent_messages[1]
      session_new_sent.observer.on_complete("success", {
        sessionId = "model-switch-session",
        models = { currentModelId = "different-model" },
      })
      test_utils.next_frame()

      -- Should have sent session/set_model
      local set_model_msg = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/set_model" then
          set_model_msg = sent.message
          break
        end
      end

      assert(set_model_msg, "session/set_model should have been sent")
      eq("model-switch-session", set_model_msg.params.sessionId)
      eq("test-model", set_model_msg.params.modelId)
    end)

    it("sends prompt after model switch succeeds", function()
      local session, _ = create_active_session({ skip_activation = true })

      -- Server returns different model
      local session_new_sent = sent_messages[1]
      session_new_sent.observer.on_complete("success", {
        sessionId = "model-switch-session",
        models = { currentModelId = "different-model" },
      })
      test_utils.next_frame()

      -- Find and complete the set_model request
      local set_model_sent = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/set_model" then
          set_model_sent = sent
          break
        end
      end

      assert(set_model_sent, "session/set_model should have been sent")
      set_model_sent.observer.on_complete("success", {})
      test_utils.next_frame()

      -- Now session/prompt should have been sent
      local prompt_msg = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/prompt" then
          prompt_msg = sent.message
          break
        end
      end

      assert(
        prompt_msg,
        "session/prompt should have been sent after model switch"
      )
      eq("model-switch-session", prompt_msg.params.sessionId)
    end)

    it("continues with prompt even when model switch fails", function()
      local session, _ = create_active_session({ skip_activation = true })

      -- Server returns different model
      local session_new_sent = sent_messages[1]
      session_new_sent.observer.on_complete("success", {
        sessionId = "model-switch-session",
        models = { currentModelId = "different-model" },
      })
      test_utils.next_frame()

      -- Find and fail the set_model request
      local set_model_sent = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/set_model" then
          set_model_sent = sent
          break
        end
      end

      assert(set_model_sent, "session/set_model should have been sent")
      set_model_sent.observer.on_complete("failed", "Model not available")
      test_utils.next_frame()

      -- session/prompt should still be sent (fallback to default model)
      local prompt_msg = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/prompt" then
          prompt_msg = sent.message
          break
        end
      end

      assert(
        prompt_msg,
        "session/prompt should still be sent after model switch failure"
      )
    end)

    it("fails when session/prompt fails", function()
      local session, _ = create_active_session({ skip_activation = true })

      -- Complete session/new successfully
      local session_new_sent = sent_messages[1]
      session_new_sent.observer.on_complete("success", {
        sessionId = "prompt-fail-session",
        models = { currentModelId = "test-model" },
      })
      test_utils.next_frame()

      -- Find and fail the prompt request
      local prompt_sent = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/prompt" then
          prompt_sent = sent
          break
        end
      end

      assert(prompt_sent, "session/prompt should have been sent")
      prompt_sent.observer.on_complete("failed", "Rate limited")
      test_utils.next_frame()

      eq("failed", observer_calls.on_complete.status)
      assert(
        observer_calls.on_complete.result:find("Failed to send prompt"),
        "Should mention failed to send prompt"
      )
    end)

    it("skips model switch when models match", function()
      local session, _ = create_active_session({ skip_activation = true })

      -- Server returns same model as requested
      local session_new_sent = sent_messages[1]
      session_new_sent.observer.on_complete("success", {
        sessionId = "same-model-session",
        models = { currentModelId = "test-model" },
      })
      test_utils.next_frame()

      -- Should NOT have sent session/set_model
      local set_model_msg = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/set_model" then
          set_model_msg = sent.message
          break
        end
      end

      eq(nil, set_model_msg)

      -- But should have sent session/prompt directly
      local prompt_msg = nil
      for _, sent in ipairs(sent_messages) do
        if sent.message and sent.message.method == "session/prompt" then
          prompt_msg = sent.message
          break
        end
      end

      assert(prompt_msg, "session/prompt should have been sent directly")
    end)
  end)
end)
