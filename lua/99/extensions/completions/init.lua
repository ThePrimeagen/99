--- A provider for completion tokens (#rules, @files) used in the prompt.
--- @class _99.CompletionProvider
--- @field trigger string
--- @field name string
--- @field get_items fun(): CompletionItem[]
--- @field is_valid fun(token: string): boolean
--- @field resolve fun(token: string): string|nil

--- @class _99.Reference
--- @field content string

--- @type _99.CompletionProvider[]
local providers = {}

local M = {}

--- @param provider _99.CompletionProvider
function M.register(provider)
  for i, p in ipairs(providers) do
    if p.trigger == provider.trigger then
      providers[i] = provider
      return
    end
  end
  table.insert(providers, provider)
end

--- @return string[]
function M.get_trigger_characters()
  local chars = {}
  for _, p in ipairs(providers) do
    table.insert(chars, p.trigger)
  end
  return chars
end

--- @return string
function M.get_keyword_pattern()
  local triggers = {}
  for _, p in ipairs(providers) do
    table.insert(triggers, p.trigger)
  end
  return "[" .. table.concat(triggers) .. "]\\k*"
end

--- @param prompt_text string
--- @return _99.Reference[]
function M.parse(prompt_text)
  local refs = {}
  for _, provider in ipairs(providers) do
    local pattern = provider.trigger:gsub(
      "([%%%^%$%(%)%.%[%]%*%+%-%?])",
      "%%%1"
    ) .. "%S+"
    for word in prompt_text:gmatch(pattern) do
      local token = word:sub(#provider.trigger + 1)
      if provider.is_valid(token) then
        local content = provider.resolve(token)
        if content then
          table.insert(refs, { content = content })
        end
      end
    end
  end
  return refs
end

--- @param trigger_char string
--- @return CompletionItem[]
function M.get_completions(trigger_char)
  for _, provider in ipairs(providers) do
    if provider.trigger == trigger_char then
      return provider.get_items()
    end
  end
  return {}
end

--- Detect which trigger character is active in the text before the cursor.
--- @param cursor_before string text before cursor position
--- @return string | nil trigger the active trigger character, or nil
function M.detect_trigger(cursor_before)
  for _, char in ipairs(M.get_trigger_characters()) do
    local pattern = char:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1") .. "%S*$"
    if cursor_before:match(pattern) then
      return char
    end
  end
  return nil
end

function M._reset()
  providers = {}
end

return M
