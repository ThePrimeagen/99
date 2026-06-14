-- luacheck: globals describe it assert
local eq = assert.are.same
local Providers = require("99.providers")

describe("providers", function()
  describe("OpenCodeProvider", function()
    it("builds correct command with model", function()
      local request = { model = "anthropic/claude-sonnet-4-5" }
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
      eq(
        "opencode/claude-sonnet-4-5",
        Providers.OpenCodeProvider._get_default_model()
      )
    end)
  end)

  describe("ClaudeCodeProvider", function()
    it("builds correct command with model", function()
      local request = { model = "anthropic/claude-sonnet-4-5" }
      local cmd =
        Providers.ClaudeCodeProvider._build_command(nil, "test query", request)
      eq({
        "claude",
        "--dangerously-skip-permissions",
        "--model",
        "anthropic/claude-sonnet-4-5",
        "--print",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq("claude-sonnet-4-5", Providers.ClaudeCodeProvider._get_default_model())
    end)
  end)

  describe("CursorAgentProvider", function()
    it("builds correct command with model", function()
      local request = { model = "anthropic/claude-sonnet-4-5" }
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
      eq("sonnet-4.5", Providers.CursorAgentProvider._get_default_model())
    end)
  end)

  describe("GeminiCLIProvider", function()
    it("builds correct command with model", function()
      local request = { model = "gemini-2.5-pro" }
      local cmd =
        Providers.GeminiCLIProvider._build_command(nil, "test query", request)
      eq({
        "gemini",
        "--approval-mode",
        "auto_edit",
        "--model",
        "gemini-2.5-pro",
        "--prompt",
        "test query",
      }, cmd)
    end)

    it("has correct default model", function()
      eq("auto", Providers.GeminiCLIProvider._get_default_model())
    end)
  end)

  describe("provider integration", function()
    it("can be set as provider override", function()
      local _99 = require("99")

      _99.setup({ provider = Providers.ClaudeCodeProvider })
      local state = _99.__get_state()
      eq(Providers.ClaudeCodeProvider, state.provider_override)
    end)

    it(
      "uses OpenCodeProvider default model when no provider or model specified",
      function()
        local _99 = require("99")

        _99.setup({})
        local state = _99.__get_state()
        eq("opencode/claude-sonnet-4-5", state.model)
      end
    )

    it(
      "uses ClaudeCodeProvider default model when provider specified but no model",
      function()
        local _99 = require("99")

        _99.setup({ provider = Providers.ClaudeCodeProvider })
        local state = _99.__get_state()
        eq("claude-sonnet-4-5", state.model)
      end
    )

    it(
      "uses CursorAgentProvider default model when provider specified but no model",
      function()
        local _99 = require("99")

        _99.setup({ provider = Providers.CursorAgentProvider })
        local state = _99.__get_state()
        eq("sonnet-4.5", state.model)
      end
    )

    it(
      "uses GeminiCLIProvider default model when provider specified but no model",
      function()
        local _99 = require("99")

        _99.setup({ provider = Providers.GeminiCLIProvider })
        local state = _99.__get_state()
        eq("auto", state.model)
      end
    )

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

  describe("provider_extra_args", function()
    it("stores provider_extra_args on state", function()
      local _99 = require("99")
      _99.setup({
        provider_extra_args = { "--no-session-persistence" },
      })
      local state = _99.__get_state()
      eq({ "--no-session-persistence" }, state.provider_extra_args)
    end)

    it("defaults provider_extra_args to empty table", function()
      local _99 = require("99")
      _99.setup({})
      local state = _99.__get_state()
      eq({}, state.provider_extra_args)
    end)
  end)

  describe("BaseProvider", function()
    it("all providers have make_request", function()
      eq("function", type(Providers.OpenCodeProvider.make_request))
      eq("function", type(Providers.ClaudeCodeProvider.make_request))
      eq("function", type(Providers.CursorAgentProvider.make_request))
      eq("function", type(Providers.GeminiCLIProvider.make_request))
    end)
  end)

  describe("stdout_as_response", function()
    it("is false for providers that write to temp file", function()
      eq(false, Providers.OpenCodeProvider._stdout_as_response())
      eq(false, Providers.KiroProvider._stdout_as_response())
      eq(false, Providers.GeminiCLIProvider._stdout_as_response())
    end)

    it("is true for providers using --print flag", function()
      eq(true, Providers.ClaudeCodeProvider._stdout_as_response())
      eq(true, Providers.CursorAgentProvider._stdout_as_response())
    end)
  end)

  describe("strip_markdown_fences", function()
    it("strips code fences with language identifier", function()
      local input = "```python\nis_inventory: bool,\n```"
      eq(
        "is_inventory: bool,",
        Providers.BaseProvider.strip_markdown_fences(input)
      )
    end)

    it("strips code fences without language identifier", function()
      local input = "```\nis_inventory: bool,\n```"
      eq(
        "is_inventory: bool,",
        Providers.BaseProvider.strip_markdown_fences(input)
      )
    end)

    it("returns text unchanged when no fences present", function()
      local input = "is_inventory: bool,"
      eq(
        "is_inventory: bool,",
        Providers.BaseProvider.strip_markdown_fences(input)
      )
    end)

    it("handles multi-line content inside fences", function()
      local input = "```lua\nlocal x = 1\nlocal y = 2\nreturn x + y\n```"
      eq(
        "local x = 1\nlocal y = 2\nreturn x + y",
        Providers.BaseProvider.strip_markdown_fences(input)
      )
    end)

    it("handles empty content inside fences", function()
      local input = "```\n```"
      eq("", Providers.BaseProvider.strip_markdown_fences(input))
    end)

    it("trims to empty string for whitespace-only input", function()
      eq("", vim.trim(Providers.BaseProvider.strip_markdown_fences("\n")))
      eq("", vim.trim(Providers.BaseProvider.strip_markdown_fences("  \n  ")))
    end)

    it("does not strip fences that are not wrapping the whole text", function()
      local input = "some text\n```python\ncode\n```\nmore text"
      eq(input, Providers.BaseProvider.strip_markdown_fences(input))
    end)
  end)
end)
