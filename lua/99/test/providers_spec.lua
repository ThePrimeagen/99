-- luacheck: globals describe it assert
local eq = assert.are.same
local Providers = require("99.providers")
local Models = require("99.models")

describe("providers", function()
  describe("OpenCodeProvider", function()
    it("builds correct command with model", function()
      local request = { context = { model = "anthropic/claude-sonnet-4-5" } }
      local cmd =
        Providers.OpenCodeProvider._build_command(nil, "test query", request)
      eq({
        "opencode",
        "run",
        "--agent",
        "build",
        "-m",
        "anthropic/claude-sonnet-4-5",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq(Models.sonnet_4_5, Providers.OpenCodeProvider._get_default_model())
    end)
  end)

  describe("ClaudeCodeProvider", function()
    it("builds correct command with model", function()
      local request = { context = { model = "claude-sonnet-4-5" } }
      local cmd =
        Providers.ClaudeCodeProvider._build_command(nil, "test query", request)
      eq({
        "claude",
        "--dangerously-skip-permissions",
        "--model",
        "claude-sonnet-4-5",
        "--print",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq(Models.sonnet_4_5, Providers.ClaudeCodeProvider._get_default_model())
    end)
  end)

  describe("CursorAgentProvider", function()
    it("builds correct command with model", function()
      local request = { context = { model = "anthropic/claude-sonnet-4-5" } }
      local cmd =
        Providers.CursorAgentProvider._build_command(nil, "test query", request)
      eq({
        "cursor-agent",
        "--model",
        "anthropic/claude-sonnet-4-5",
        "--print",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq(Models.sonnet_4_5, Providers.CursorAgentProvider._get_default_model())
    end)
  end)

  describe("provider integration", function()
    it("can be set as provider override", function()
      local _99 = require("99")

      _99.setup({ provider = Providers.ClaudeCodeProvider })
      local state = _99.__get_state()
      eq(Providers.ClaudeCodeProvider, state.provider_override)
    end)

    it("uses default Model when no provider or model specified", function()
      local _99 = require("99")

      _99.setup({})
      local state = _99.__get_state()
      eq(Models.sonnet_4_5, state.model)
    end)

    it("uses default Model when provider specified but no model", function()
      local _99 = require("99")

      _99.setup({ provider = Providers.ClaudeCodeProvider })
      local state = _99.__get_state()
      eq(Models.sonnet_4_5, state.model)
    end)

    it("uses default Model when CursorAgent specified but no model", function()
      local _99 = require("99")

      _99.setup({ provider = Providers.CursorAgentProvider })
      local state = _99.__get_state()
      eq(Models.sonnet_4_5, state.model)
    end)

    it("uses custom model when both provider and model specified", function()
      local _99 = require("99")

      _99.setup({
        provider = Providers.ClaudeCodeProvider,
        model = "custom-model",
      })
      local state = _99.__get_state()
      eq("custom-model", state.model)
    end)
  end)

  describe("BaseProvider", function()
    it("all providers have make_request", function()
      eq("function", type(Providers.OpenCodeProvider.make_request))
      eq("function", type(Providers.ClaudeCodeProvider.make_request))
      eq("function", type(Providers.CursorAgentProvider.make_request))
    end)
  end)
end)
