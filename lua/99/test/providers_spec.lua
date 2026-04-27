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

  describe("stdout fallback for tutorial operation", function()
    local test_utils = require("99.test.test_utils")
    local Prompt = require("99.prompt")

    it("uses stdout when temp file is empty for tutorial context", function()
      local _99 = require("99")
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({}, provider))

      local state = _99.__get_state()
      local context = Prompt.tutorial(state)
      context.user_prompt = "test tutorial"
      context:finalize()

      -- Create the temp file but leave it empty
      local tmp_file = context.tmp_file
      local file = io.open(tmp_file, "w")
      if file then
        file:write("")
        file:close()
      end

      local complete_status = nil
      local complete_result = nil

      local observer = {
        on_start = function() end,
        on_complete = function(status, res)
          complete_status = status
          complete_result = res
        end,
        on_stderr = function() end,
        on_stdout = function() end,
      }

      -- Stub vim.system to simulate OpenCode writing to stdout instead of temp file
      local original_vim_system = vim.system
      local stdout_chunks =
        { "# Tutorial Title\n", "\n", "This is tutorial content from stdout." }
      local captured_stdout = {}

      vim.system = function(_cmd, opts, callback)
        -- Simulate stdout callback with tutorial content
        for _, chunk in ipairs(stdout_chunks) do
          if opts.stdout then
            opts.stdout(nil, chunk)
            table.insert(captured_stdout, chunk)
          end
        end

        -- Simulate process exit with code 0
        vim.schedule(function()
          callback({
            code = 0,
            stdout = table.concat(stdout_chunks),
            stderr = "",
          })
        end)

        -- Return a mock process object
        return { pid = 12345 }
      end

      -- Make the request
      Providers.OpenCodeProvider:make_request("test query", context, observer)

      -- Wait for the async callback
      test_utils.next_frame()

      -- Restore original vim.system
      vim.system = original_vim_system

      -- Verify that on_complete was called with success and the stdout content
      eq("success", complete_status)
      eq(
        "# Tutorial Title\n\nThis is tutorial content from stdout.",
        complete_result
      )
    end)

    it("does NOT use stdout fallback for search operation", function()
      local _99 = require("99")
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({}, provider))

      local state = _99.__get_state()
      local context = Prompt.search(state)
      context.user_prompt = "test search"
      context:finalize()

      -- Create the temp file but leave it empty
      local tmp_file = context.tmp_file
      local file = io.open(tmp_file, "w")
      if file then
        file:write("")
        file:close()
      end

      local complete_status = nil
      local complete_result = nil

      local observer = {
        on_start = function() end,
        on_complete = function(status, res)
          complete_status = status
          complete_result = res
        end,
        on_stderr = function() end,
        on_stdout = function() end,
      }

      -- Stub vim.system to simulate OpenCode writing to stdout instead of temp file
      local original_vim_system = vim.system
      local stdout_chunks = { "/path/to/file.lua:1:1,5,some search result\n" }

      vim.system = function(_cmd, opts, callback)
        -- Simulate stdout callback with search content
        for _, chunk in ipairs(stdout_chunks) do
          if opts.stdout then
            opts.stdout(nil, chunk)
          end
        end

        -- Simulate process exit with code 0
        vim.schedule(function()
          callback({
            code = 0,
            stdout = table.concat(stdout_chunks),
            stderr = "",
          })
        end)

        -- Return a mock process object
        return { pid = 12345 }
      end

      -- Make the request
      Providers.OpenCodeProvider:make_request("test query", context, observer)

      -- Wait for the async callback
      test_utils.next_frame()

      -- Restore original vim.system
      vim.system = original_vim_system

      -- Verify that on_complete was called with success but EMPTY result (not stdout)
      eq("success", complete_status)
      eq("", complete_result)
    end)

    it("uses temp file content when it is non-empty for tutorial", function()
      local _99 = require("99")
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({}, provider))

      local state = _99.__get_state()
      local context = Prompt.tutorial(state)
      context.user_prompt = "test tutorial"
      context:finalize()

      -- Create the temp file with actual content
      local tmp_file = context.tmp_file
      local file = io.open(tmp_file, "w")
      if file then
        file:write("# Tutorial from temp file\n\nThis is the real content.")
        file:close()
      end

      local complete_status = nil
      local complete_result = nil

      local observer = {
        on_start = function() end,
        on_complete = function(status, res)
          complete_status = status
          complete_result = res
        end,
        on_stderr = function() end,
        on_stdout = function() end,
      }

      -- Stub vim.system
      local original_vim_system = vim.system
      local stdout_chunks =
        { "# Tutorial from stdout\n\nThis should be ignored." }

      vim.system = function(_cmd, opts, callback)
        -- Simulate stdout callback
        for _, chunk in ipairs(stdout_chunks) do
          if opts.stdout then
            opts.stdout(nil, chunk)
          end
        end

        -- Simulate process exit with code 0
        vim.schedule(function()
          callback({
            code = 0,
            stdout = table.concat(stdout_chunks),
            stderr = "",
          })
        end)

        return { pid = 12345 }
      end

      -- Make the request
      Providers.OpenCodeProvider:make_request("test query", context, observer)

      -- Wait for the async callback
      test_utils.next_frame()

      -- Restore original vim.system
      vim.system = original_vim_system

      -- Verify that on_complete was called with temp file content, not stdout
      eq("success", complete_status)
      eq(
        "# Tutorial from temp file\n\nThis is the real content.",
        complete_result
      )
    end)
  end)
end)
