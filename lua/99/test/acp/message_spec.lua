-- luacheck: globals describe it assert
local eq = assert.are.same
local Message = require("99.acp.message")

describe("acp/message", function()
  describe("initialize_request", function()
    local msg = Message.initialize_request()

    it("has jsonrpc 2.0", function()
      eq("2.0", msg.jsonrpc)
    end)

    it("has id of 1", function()
      eq(1, msg.id)
    end)

    it("has method initialize", function()
      eq("initialize", msg.method)
    end)

    it("has protocolVersion 1", function()
      eq(1, msg.params.protocolVersion)
    end)

    it("has empty clientCapabilities", function()
      eq({}, msg.params.clientCapabilities)
    end)

    it("has clientInfo", function()
      eq("99.nvim", msg.params.clientInfo.name)
      eq("0.1.0", msg.params.clientInfo.version)
    end)
  end)

  describe("session_new_request", function()
    it("has method session/new", function()
      local msg = Message.session_new_request("/test/path", nil)
      eq("session/new", msg.method)
    end)

    it("includes cwd in params", function()
      local msg = Message.session_new_request("/test/path", nil)
      eq("/test/path", msg.params.cwd)
    end)

    it("includes empty mcpServers", function()
      local msg = Message.session_new_request("/test/path", nil)
      eq({}, msg.params.mcpServers)
    end)

    it("includes modelId when model provided", function()
      local msg =
        Message.session_new_request("/test/path", "anthropic/claude-sonnet-4-5")
      eq("anthropic/claude-sonnet-4-5", msg.params.modelId)
    end)

    it("includes _meta.modelId when model provided", function()
      local msg =
        Message.session_new_request("/test/path", "anthropic/claude-sonnet-4-5")
      eq("anthropic/claude-sonnet-4-5", msg.params._meta.modelId)
    end)

    it("omits modelId when model is nil", function()
      local msg = Message.session_new_request("/test/path", nil)
      eq(nil, msg.params.modelId)
      eq(nil, msg.params._meta)
    end)
  end)

  describe("session_set_model_request", function()
    local msg = Message.session_set_model_request(
      "session-123",
      "anthropic/claude-opus-4"
    )

    it("has method session/set_model", function()
      eq("session/set_model", msg.method)
    end)

    it("includes sessionId in params", function()
      eq("session-123", msg.params.sessionId)
    end)

    it("includes modelId in params", function()
      eq("anthropic/claude-opus-4", msg.params.modelId)
    end)
  end)

  describe("session_prompt_request", function()
    local context = {
      ai_context = { "context block 1", "context block 2" },
      tmp_file = "/tmp/test-output.txt",
    }
    local msg =
      Message.session_prompt_request("session-123", "do something", context)

    it("has method session/prompt", function()
      eq("session/prompt", msg.method)
    end)

    it("includes sessionId in params", function()
      eq("session-123", msg.params.sessionId)
    end)

    it("builds content blocks from ai_context", function()
      eq({ type = "text", text = "context block 1" }, msg.params.prompt[1])
      eq({ type = "text", text = "context block 2" }, msg.params.prompt[2])
    end)

    it("appends query with tmp_file instruction as last block", function()
      local last_block = msg.params.prompt[3]
      eq("text", last_block.type)
      assert.is_not_nil(last_block.text:find("do something", 1, true))
      assert.is_not_nil(last_block.text:find("/tmp/test%-output%.txt"))
    end)
  end)

  describe("session_cancel_notification", function()
    local msg = Message.session_cancel_notification("session-123")

    it("has method session/cancel", function()
      eq("session/cancel", msg.method)
    end)

    it("has no id field", function()
      eq(nil, msg.id)
    end)

    it("includes sessionId in params", function()
      eq("session-123", msg.params.sessionId)
    end)
  end)
end)
