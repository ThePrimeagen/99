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

--- @param provider _99.Providers.BaseProvider?
--- @param opts table?
function M.select_model(provider, opts)
  if type(provider) == "table" and opts == nil and not is_selectable_provider(provider) then
    opts = provider
    provider = nil
  end

  opts = opts or {}
  M.get_models(provider, function(models, current)
    vim.ui.select(models, {
      prompt = opts.prompt or ("99: Select Model (current: " .. current .. ")"),
      format_item = opts.format_item,
      kind = opts.kind or "99.model",
    }, function(choice)
      if not choice then
        return
      end
      M.on_model_selected(choice)
    end)
  end)
end

--- @param opts table?
function M.select_provider(opts)
  opts = opts or {}
  local info = M.get_providers()

  vim.ui.select(info.names, {
    prompt = opts.prompt
      or ("99: Select Provider (current: " .. info.current .. ")"),
    format_item = opts.format_item,
    kind = opts.kind or "99.provider",
  }, function(choice)
    if not choice then
      return
    end
    M.on_provider_selected(choice, info.lookup)
  end)
end

return M
