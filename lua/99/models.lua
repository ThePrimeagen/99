--- @type table<string, string>
local provider_keys = {
  OpenCodeProvider = "opencode",
  ClaudeCodeProvider = "claude",
  CursorAgentProvider = "cursor",
  KiroProvider = "kiro",
}

--- @class _99.Models.Model
--- @field opencode string?
--- @field claude string?
--- @field codex string?
--- @field cursor string?
--- @field kiro string?

local M = {}

--- raw strings pass through unchanged
--- @param model string | _99.Models.Model
--- @param provider_name string
--- @return string
function M.resolve(model, provider_name)
  if type(model) == "string" then
    return model
  end
  local key = provider_keys[provider_name]
  assert(key, "unknown provider: " .. tostring(provider_name))
  local resolved = model[key]
  assert(
    resolved,
    string.format(
      "model has no mapping for provider %s (key: %s)",
      provider_name,
      key
    )
  )
  return resolved
end

--- opencode + claude

M.opus_4_6 = {
  opencode = "anthropic/claude-opus-4-6",
  claude = "claude-opus-4-6",
}

M.opus_4_5 = {
  opencode = "anthropic/claude-opus-4-5",
  claude = "claude-opus-4-5",
}

M.sonnet_4_5 = {
  opencode = "anthropic/claude-sonnet-4-5",
  claude = "claude-sonnet-4-5",
}

M.haiku_4_5 = {
  opencode = "anthropic/claude-haiku-4-5",
  claude = "claude-haiku-4-5",
}

--- opencode + codex

M.gpt_5_1_codex_max = {
  opencode = "openai/gpt-5.1-codex-max",
  codex = "gpt-5.1-codex-max",
}

M.gpt_5_1_codex = {
  opencode = "openai/gpt-5.1-codex",
  codex = "gpt-5.1-codex",
}

M.gpt_5_1_codex_mini = {
  opencode = "openai/gpt-5.1-codex-mini",
  codex = "gpt-5.1-codex-mini",
}

return M
