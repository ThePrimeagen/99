local _99 = require("99")

local M = {}

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
    table.insert(names, name)
    lookup[name] = provider
  end
  table.sort(names)
  return {
    names = names,
    lookup = lookup,
    current = _99.get_provider()._get_provider_name(),
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
  _99.set_provider(lookup[name])
  vim.notify(
    "99: Provider set to " .. name .. " (model: " .. _99.get_model() .. ")"
  )
end

return M
