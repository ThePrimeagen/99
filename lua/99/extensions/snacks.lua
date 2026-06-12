local pickers_util = require("99.extensions.pickers")

local M = {}

---@param provider _99.Providers.BaseProvider?
function M.select_model(provider)
  local ok, snacks = pcall(require, "snacks")
  if
    not ok
    or not snacks.picker
    or type(snacks.picker.select) ~= "function"
  then
    vim.notify(
      "99: snacks.nvim picker is required for this extension",
      vim.log.levels.ERROR
    )
    return
  end

  pickers_util.get_models(provider, function(models, current)
    snacks.picker.select(models, {
      prompt = "99: Select Model (current: " .. current .. ")",
      snacks = {
        on_show = function(picker)
          picker.list:view(pickers_util.index_of(models, current))
        end,
      },
    }, function(selected)
      if not selected then
        return
      end
      pickers_util.on_model_selected(selected)
    end)
  end)
end

function M.select_provider()
  local ok, snacks = pcall(require, "snacks")
  if
    not ok
    or not snacks.picker
    or type(snacks.picker.select) ~= "function"
  then
    vim.notify(
      "99: snacks.nvim picker is required for this extension",
      vim.log.levels.ERROR
    )
    return
  end

  local info = pickers_util.get_providers()

  snacks.picker.select(info.names, {
    prompt = "99: Select Provider (current: " .. info.current .. ")",
    format_item = function(item)
      return item
    end,
    snacks = {
      on_show = function(picker)
        picker.list:view(pickers_util.index_of(info.names, info.current))
      end,
    },
  }, function(selected)
    if not selected then
      return
    end
    pickers_util.on_provider_selected(selected, info.lookup)
  end)
end

return M
