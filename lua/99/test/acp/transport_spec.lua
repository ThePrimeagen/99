-- luacheck: globals describe it assert before_each
local eq = assert.are.same
local ACPTransport = require("99.acp.transport")
local Logger = require("99.logger.logger")
local test_utils = require("99.test.test_utils")

describe("acp/transport", function()
  local transport
  local written
  local mock_proc

  before_each(function()
    written = {}
    mock_proc = {}
    mock_proc.write = function(_, data)
      table.insert(written, data)
    end
    local mock_logger = Logger:set_id(1)
    transport = ACPTransport.new(mock_proc, mock_logger, nil)
  end)

  describe("_handle_stdout", function()
    it("buffers incomplete line without newline", function()
      transport:_handle_stdout('{"partial":')
      eq('{"partial":', transport._stdout_buffer)
    end)

    it("processes complete line when newline received", function()
      local handled = {}
      transport._handle_message = function(_, line)
        table.insert(handled, line)
      end

      transport:_handle_stdout('{"complete":true}\n')
      eq("", transport._stdout_buffer)
      eq({ '{"complete":true}' }, handled)
    end)

    it("handles multiple complete lines in one chunk", function()
      local handled = {}
      transport._handle_message = function(_, line)
        table.insert(handled, line)
      end

      transport:_handle_stdout('{"first":1}\n{"second":2}\n')
      eq({ '{"first":1}', '{"second":2}' }, handled)
    end)

    it("handles line split across multiple chunks", function()
      local handled = {}
      transport._handle_message = function(_, line)
        table.insert(handled, line)
      end

      transport:_handle_stdout('{"split":')
      transport:_handle_stdout('"value"}\n')
      eq({ '{"split":"value"}' }, handled)
    end)

    it("ignores empty lines", function()
      local handled = {}
      transport._handle_message = function(_, line)
        table.insert(handled, line)
      end

      transport:_handle_stdout('\n\n{"data":1}\n\n')
      eq({ '{"data":1}' }, handled)
    end)
  end)

  describe("send", function()
    it("assigns incrementing rpc_id starting at 2", function()
      local observer = { on_complete = function() end }

      transport:send(100, { method = "test1" }, observer)
      transport:send(101, { method = "test2" }, observer)

      local json1 = written[1]:gsub("\n", "")
      local json2 = written[2]:gsub("\n", "")
      eq(2, vim.json.decode(json1).id)
      eq(3, vim.json.decode(json2).id)
    end)

    it("stores observer for response routing", function()
      local observer = { on_complete = function() end }
      transport:send(100, { method = "test" }, observer)

      eq(observer, transport._pending_requests[2])
    end)

    it("writes JSON with newline to proc", function()
      local observer = { on_complete = function() end }
      transport:send(100, { method = "test" }, observer)

      assert.is_true(written[1]:sub(-1) == "\n")
      local json = written[1]:gsub("\n", "")
      local decoded = vim.json.decode(json)
      eq("test", decoded.method)
    end)
  end)

  describe("cancel_request", function()
    it("removes observer from pending", function()
      local observer = { on_complete = function() end }
      transport:send(100, { method = "test" }, observer)

      eq(observer, transport._pending_requests[2])
      transport:cancel_request(100)
      eq(nil, transport._pending_requests[2])
    end)

    it("handles cancelling non-existent request", function()
      transport:cancel_request(999)
    end)
  end)

  describe("_handle_message routing", function()
    it("routes response (id + result) to _handle_response", function()
      local called = false
      transport._handle_response = function()
        called = true
      end

      transport:_handle_message('{"id":2,"result":{"sessionId":"abc"}}')
      eq(true, called)
    end)

    it("routes error (id + error) to _handle_error", function()
      local called = false
      transport._handle_error = function()
        called = true
      end

      transport:_handle_message('{"id":2,"error":{"code":-1,"message":"fail"}}')
      eq(true, called)
    end)

    it("routes notification (method, no id) to _handle_notification", function()
      local called = false
      transport._handle_notification = function()
        called = true
      end

      transport:_handle_message('{"method":"session/update","params":{}}')
      eq(true, called)
    end)
  end)

  describe("_handle_response", function()
    it("calls observer.on_complete with session result", function()
      local result = nil
      local observer = {
        on_complete = function(status, res)
          result = { status = status, res = res }
        end,
      }
      transport:send(100, { method = "session/new" }, observer)
      test_utils.next_frame()

      transport:_handle_response({ id = 2, result = { sessionId = "abc-123" } })
      test_utils.next_frame()

      eq("success", result.status)
      eq("abc-123", result.res.sessionId)
    end)

    it("calls observer.on_complete with stopReason", function()
      local result = nil
      local observer = {
        on_complete = function(status, res)
          result = { status = status, res = res }
        end,
      }
      transport:send(100, { method = "session/prompt" }, observer)
      test_utils.next_frame()

      transport:_handle_response({
        id = 2,
        result = { stopReason = "end_turn" },
      })
      test_utils.next_frame()

      eq("success", result.status)
      eq("end_turn", result.res)
    end)

    it("removes observer from pending after calling", function()
      local observer = { on_complete = function() end }
      transport:send(100, { method = "test" }, observer)

      eq(observer, transport._pending_requests[2])
      transport:_handle_response({ id = 2, result = {} })
      eq(nil, transport._pending_requests[2])
    end)
  end)

  describe("_handle_error", function()
    it("calls observer.on_complete with failed status", function()
      local result = nil
      local observer = {
        on_complete = function(status, res)
          result = { status = status, res = res }
        end,
      }
      transport:send(100, { method = "test" }, observer)
      test_utils.next_frame()

      transport:_handle_error({
        id = 2,
        error = { code = -1, message = "test error" },
      })
      test_utils.next_frame()

      eq("failed", result.status)
      assert.is_true(result.res:find("test error") ~= nil)
    end)
  end)

  describe("on_notification", function()
    it("routes notifications to registered handler", function()
      local received = nil
      transport:on_notification(function(notification)
        received = notification
      end)

      transport:_handle_notification({
        method = "session/update",
        params = { test = 1 },
      })
      test_utils.next_frame()

      eq("session/update", received.method)
      eq(1, received.params.test)
    end)
  end)

  describe("_handle_message routing for agent requests", function()
    it(
      "routes request (id + method, no result) to _handle_agent_request",
      function()
        local called = false
        transport._handle_agent_request = function()
          called = true
        end

        transport:_handle_message(
          '{"id":5,"method":"session/request_permission","params":{}}'
        )
        eq(true, called)
      end
    )
  end)

  describe("respond", function()
    it("sends JSON-RPC response with result", function()
      transport:respond(
        5,
        { outcome = { outcome = "selected", optionId = "once" } }
      )

      eq(1, #written)
      local json = written[1]:gsub("\n", "")
      local decoded = vim.json.decode(json)
      eq("2.0", decoded.jsonrpc)
      eq(5, decoded.id)
      eq("selected", decoded.result.outcome.outcome)
      eq("once", decoded.result.outcome.optionId)
    end)
  end)

  describe("respond_error", function()
    it("sends JSON-RPC error response", function()
      transport:respond_error(5, -32601, "Method not found")

      eq(1, #written)
      local json = written[1]:gsub("\n", "")
      local decoded = vim.json.decode(json)
      eq("2.0", decoded.jsonrpc)
      eq(5, decoded.id)
      eq(-32601, decoded.error.code)
      eq("Method not found", decoded.error.message)
    end)
  end)

  describe("_default_request_handler", function()
    it("auto-approves session/request_permission", function()
      transport:_default_request_handler({
        id = 10,
        method = "session/request_permission",
        params = {
          sessionId = "sess-1",
          toolCall = { toolCallId = "call-1", title = "bash" },
        },
      })

      eq(1, #written)
      local json = written[1]:gsub("\n", "")
      local decoded = vim.json.decode(json)
      eq(10, decoded.id)
      eq("selected", decoded.result.outcome.outcome)
      eq("once", decoded.result.outcome.optionId)
    end)

    it("returns error for unknown method", function()
      transport:_default_request_handler({
        id = 11,
        method = "unknown/method",
        params = {},
      })

      eq(1, #written)
      local json = written[1]:gsub("\n", "")
      local decoded = vim.json.decode(json)
      eq(11, decoded.id)
      eq(-32601, decoded.error.code)
      assert.is_true(decoded.error.message:find("unknown/method") ~= nil)
    end)
  end)

  describe("on_request", function()
    it(
      "routes agent requests to registered handler instead of default",
      function()
        local received = nil
        transport:on_request(function(request)
          received = request
        end)

        transport:_handle_agent_request({
          id = 15,
          method = "session/request_permission",
          params = { sessionId = "sess-2" },
        })
        test_utils.next_frame()

        eq(15, received.id)
        eq("session/request_permission", received.method)
        eq("sess-2", received.params.sessionId)
        -- Should not have auto-responded since custom handler was set
        eq(0, #written)
      end
    )
  end)
end)
