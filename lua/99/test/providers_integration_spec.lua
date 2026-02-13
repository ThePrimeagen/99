-- luacheck: globals describe it assert pending
local eq = assert.are.same
local Models = require("99.models")
local Providers = require("99.providers")

--- @param name string
--- @return boolean
local function is_available(name)
  return vim.fn.executable(name) == 1
end

local function is_ci()
  return os.getenv("CI") ~= nil or os.getenv("GITHUB_ACTIONS") ~= nil
end

--- @class ProviderFixture
--- @field name string
--- @field provider _99.Providers.BaseProvider
--- @field executable string
--- @field model_index number
--- @field key string

--- @type ProviderFixture[]
local fixtures = {
  {
    name = "OpenCodeProvider",
    provider = Providers.OpenCodeProvider,
    executable = "opencode",
    model_index = 6,
    key = "opencode",
  },
  {
    name = "ClaudeCodeProvider",
    provider = Providers.ClaudeCodeProvider,
    executable = "claude",
    model_index = 4,
    key = "claude",
  },
  {
    name = "CursorAgentProvider",
    provider = Providers.CursorAgentProvider,
    executable = "cursor-agent",
    model_index = 3,
    key = "cursor",
  },
  {
    name = "KiroProvider",
    provider = Providers.KiroProvider,
    executable = "kiro-cli",
    model_index = 5,
    key = "kiro",
  },
}

--- @type table<string, _99.Models.Model>
local cross_provider_models = {
  opus_4_6 = Models.opus_4_6,
  opus_4_5 = Models.opus_4_5,
  sonnet_4_5 = Models.sonnet_4_5,
  haiku_4_5 = Models.haiku_4_5,
  gpt_5_1_codex_max = Models.gpt_5_1_codex_max,
  gpt_5_1_codex = Models.gpt_5_1_codex,
  gpt_5_1_codex_mini = Models.gpt_5_1_codex_mini,
}

describe("providers integration", function()
  if is_ci() then
    it("skipped in CI", function()
      pending("provider CLIs are not available in CI")
    end)
    return
  end

  for _, fixture in ipairs(fixtures) do
    describe(fixture.name, function()
      if not is_available(fixture.executable) then
        it("skipped (" .. fixture.executable .. " not installed)", function()
          pending(fixture.executable .. " not found on PATH")
        end)
        return
      end

      it(fixture.executable .. " is on PATH", function()
        eq(1, vim.fn.executable(fixture.executable))
      end)

      for model_name, m in pairs(cross_provider_models) do
        if m[fixture.key] then
          it(
            "builds command with " .. model_name .. " resolved model",
            function()
              local resolved = Models.resolve(m, fixture.name)
              local request = { context = { model = resolved } }
              local cmd =
                fixture.provider._build_command(nil, "test query", request)
              eq(resolved, cmd[fixture.model_index])
            end
          )
        end
      end

      it("builds command with default model", function()
        local default = fixture.provider._get_default_model()
        if default[fixture.key] then
          local resolved = Models.resolve(default, fixture.name)
          local request = { context = { model = resolved } }
          local cmd =
            fixture.provider._build_command(nil, "test query", request)
          eq(resolved, cmd[fixture.model_index])
        else
          pending("default model has no mapping for " .. fixture.key)
        end
      end)

      it("builds command with raw string model", function()
        local request = { context = { model = "custom-raw-string" } }
        local cmd = fixture.provider._build_command(nil, "test query", request)
        eq("custom-raw-string", cmd[fixture.model_index])
      end)
    end)
  end
end)
