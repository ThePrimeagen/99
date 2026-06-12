local _99 = require("99")

local M = {}

local function is_selectable_provider(provider)
  return type(provider) == "table"
    and type(provider._get_provider_name) == "function"
    and type(provider._build_command) == "function"
end

--- @param provider _99.Providers.BaseProvider?
--- @param callback fun(models: string[], current: string): nil
function M.get_models(provider, callback)
  provider = provider or _99.get_provider()

  provider.fetch_models(function(models, err)
    if err then
      vim.notify("99: " .. err, vim.log.levels.ERROR)
      return
    end
    if not models or #models == 0 then
      vim.notify("99: No models available", vim.log.levels.WARN)
      return
    end
    callback(models, _99.get_model())
  end)
end

--- @return { names: string[], lookup: table<string, _99.Providers.BaseProvider>, current: string }
function M.get_providers()
  local names = {}
  local lookup = {}

  for name, provider in pairs(_99.Providers) do
    if is_selectable_provider(provider) then
      table.insert(names, name)
      lookup[name] = provider
    end
  end
  table.sort(names)
  local current = ""
  local current_provider = _99.get_provider()
  if is_selectable_provider(current_provider) then
    current = current_provider._get_provider_name()
  elseif #names > 0 then
    current = names[1]
  end

  return {
    names = names,
    lookup = lookup,
    current = current,
  }
end

--- @param model string
function M.on_model_selected(model)
  _99.set_model(model)
  vim.notify("99: Model set to " .. model)
end

--- @param name string
--- @param lookup table<string, _99.Providers.BaseProvider>
function M.on_provider_selected(name, lookup)
  local provider = lookup[name]
  if not provider then
    vim.notify(
      "99: Invalid provider selection: " .. tostring(name),
      vim.log.levels.ERROR
    )
    return
  end
  _99.set_provider(provider)
  vim.notify(
    "99: Provider set to " .. name .. " (model: " .. _99.get_model() .. ")"
  )
end

--- @return { levels: string[], current: string|nil }|nil
function M.get_effort_levels()
  local provider = _99.get_provider()
  local levels = provider._get_effort_levels and provider:_get_effort_levels()
  if not levels then
    vim.notify(
      "99: Current provider does not support effort levels",
      vim.log.levels.WARN
    )
    return nil
  end
  return { levels = levels, current = _99.get_effort() }
end

--- @param level string
function M.on_effort_selected(level)
  _99.set_effort(level)
  vim.notify("99: Effort set to " .. level)
end

return M
