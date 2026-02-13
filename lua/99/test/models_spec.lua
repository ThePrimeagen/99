-- luacheck: globals describe it assert
local eq = assert.are.same
local Models = require("99.models")
local Providers = require("99.providers")

describe("models", function()
  describe("resolve", function()
    it("passes through raw strings unchanged", function()
      eq(
        "some-custom-model",
        Models.resolve("some-custom-model", "OpenCodeProvider")
      )
    end)

    it("passes through raw strings for any provider", function()
      eq("my-string", Models.resolve("my-string", "ClaudeCodeProvider"))
    end)

    it("resolves opus_4_6 for OpenCodeProvider", function()
      eq(
        "anthropic/claude-opus-4-6",
        Models.resolve(Models.opus_4_6, "OpenCodeProvider")
      )
    end)

    it("resolves opus_4_6 for ClaudeCodeProvider", function()
      eq(
        "claude-opus-4-6",
        Models.resolve(Models.opus_4_6, "ClaudeCodeProvider")
      )
    end)

    it("resolves opus_4_5 for OpenCodeProvider", function()
      eq(
        "anthropic/claude-opus-4-5",
        Models.resolve(Models.opus_4_5, "OpenCodeProvider")
      )
    end)

    it("resolves opus_4_5 for ClaudeCodeProvider", function()
      eq(
        "claude-opus-4-5",
        Models.resolve(Models.opus_4_5, "ClaudeCodeProvider")
      )
    end)

    it("resolves sonnet_4_5 for OpenCodeProvider", function()
      eq(
        "anthropic/claude-sonnet-4-5",
        Models.resolve(Models.sonnet_4_5, "OpenCodeProvider")
      )
    end)

    it("resolves sonnet_4_5 for ClaudeCodeProvider", function()
      eq(
        "claude-sonnet-4-5",
        Models.resolve(Models.sonnet_4_5, "ClaudeCodeProvider")
      )
    end)

    it("resolves haiku_4_5 for OpenCodeProvider", function()
      eq(
        "anthropic/claude-haiku-4-5",
        Models.resolve(Models.haiku_4_5, "OpenCodeProvider")
      )
    end)

    it("resolves haiku_4_5 for ClaudeCodeProvider", function()
      eq(
        "claude-haiku-4-5",
        Models.resolve(Models.haiku_4_5, "ClaudeCodeProvider")
      )
    end)

    it("resolves gpt_5_1_codex_max for OpenCodeProvider", function()
      eq(
        "openai/gpt-5.1-codex-max",
        Models.resolve(Models.gpt_5_1_codex_max, "OpenCodeProvider")
      )
    end)

    it("resolves gpt_5_1_codex for OpenCodeProvider", function()
      eq(
        "openai/gpt-5.1-codex",
        Models.resolve(Models.gpt_5_1_codex, "OpenCodeProvider")
      )
    end)

    it("resolves gpt_5_1_codex_mini for OpenCodeProvider", function()
      eq(
        "openai/gpt-5.1-codex-mini",
        Models.resolve(Models.gpt_5_1_codex_mini, "OpenCodeProvider")
      )
    end)
    it("returns nil and error for missing provider mapping", function()
      local result, err = Models.resolve(Models.opus_4_6, "KiroProvider")
      eq(nil, result)
      eq("string", type(err))
    end)
  end)

  describe("model constants", function()
    it("opencode+claude models have both keys", function()
      local models = {
        Models.opus_4_6,
        Models.opus_4_5,
        Models.sonnet_4_5,
        Models.haiku_4_5,
      }
      for _, m in ipairs(models) do
        eq("string", type(m.opencode))
        eq("string", type(m.claude))
      end
    end)

    it("opencode+codex models have both keys", function()
      local models = {
        Models.gpt_5_1_codex_max,
        Models.gpt_5_1_codex,
        Models.gpt_5_1_codex_mini,
      }
      for _, m in ipairs(models) do
        eq("string", type(m.opencode))
        eq("string", type(m.codex))
      end
    end)
  end)

  describe("default model", function()
    it("all providers return a Model table from _get_default_model", function()
      eq("table", type(Providers.OpenCodeProvider._get_default_model()))
      eq("table", type(Providers.ClaudeCodeProvider._get_default_model()))
      eq("table", type(Providers.CursorAgentProvider._get_default_model()))
      eq("table", type(Providers.KiroProvider._get_default_model()))
    end)

    it("default model resolves correctly for OpenCodeProvider", function()
      local default = Providers.OpenCodeProvider._get_default_model()
      eq(
        "anthropic/claude-sonnet-4-5",
        Models.resolve(default, "OpenCodeProvider")
      )
    end)

    it("default model resolves correctly for ClaudeCodeProvider", function()
      local default = Providers.ClaudeCodeProvider._get_default_model()
      eq("claude-sonnet-4-5", Models.resolve(default, "ClaudeCodeProvider"))
    end)

    it("all providers share the same default model", function()
      local oc = Providers.OpenCodeProvider._get_default_model()
      local cc = Providers.ClaudeCodeProvider._get_default_model()
      local ca = Providers.CursorAgentProvider._get_default_model()
      local kp = Providers.KiroProvider._get_default_model()
      eq(oc, cc)
      eq(cc, ca)
      eq(ca, kp)
    end)
  end)

  describe("command building with resolved models", function()
    it("OpenCodeProvider builds correct command after resolution", function()
      local resolved = Models.resolve(Models.opus_4_6, "OpenCodeProvider")
      local request = { context = { model = resolved } }
      local cmd =
        Providers.OpenCodeProvider._build_command(nil, "test query", request)
      eq("anthropic/claude-opus-4-6", cmd[6])
    end)

    it("ClaudeCodeProvider builds correct command after resolution", function()
      local resolved = Models.resolve(Models.opus_4_6, "ClaudeCodeProvider")
      local request = { context = { model = resolved } }
      local cmd =
        Providers.ClaudeCodeProvider._build_command(nil, "test query", request)
      eq("claude-opus-4-6", cmd[4])
    end)
  end)

  describe("integration", function()
    it("accepts Model table in setup opts", function()
      local _99 = require("99")
      _99.setup({ model = Models.opus_4_6 })
      local state = _99.__get_state()
      eq(Models.opus_4_6, state.model)
    end)

    it("accepts raw string in setup opts (backward compat)", function()
      local _99 = require("99")
      _99.setup({ model = "anthropic/claude-opus-4-1" })
      local state = _99.__get_state()
      eq("anthropic/claude-opus-4-1", state.model)
    end)

    it("set_model accepts Model table", function()
      local _99 = require("99")
      _99.setup({})
      _99.set_model(Models.haiku_4_5)
      local state = _99.__get_state()
      eq(Models.haiku_4_5, state.model)
    end)

    it("default model is a Model table after setup", function()
      local _99 = require("99")
      _99.setup({})
      local state = _99.__get_state()
      eq("table", type(state.model))
    end)

    it("Models are accessible from _99.Models", function()
      local _99 = require("99")
      eq(Models.opus_4_6, _99.Models.opus_4_6)
      eq(Models.sonnet_4_5, _99.Models.sonnet_4_5)
      eq(Models.haiku_4_5, _99.Models.haiku_4_5)
      eq(Models.gpt_5_1_codex_max, _99.Models.gpt_5_1_codex_max)
    end)
  end)
end)
