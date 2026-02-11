local pickers_util = require("99.extensions.pickers")

local M = {}

-- move the current value to the top of the list so fzf opens with it focused
--- @param list string[]
--- @param current string
--- @return string[]
local function promote_current(list, current)
  local out = { unpack(list) }
  for i, item in ipairs(out) do
    if item == current then
      table.remove(out, i)
      table.insert(out, 1, current)
      break
    end
  end
  return out
end

--- @param provider _99.Providers.BaseProvider?
function M.select_model(provider)
  pickers_util.get_models(provider, function(models, current)
    local ok, fzf = pcall(require, "fzf-lua")
    if not ok then
      vim.notify(
        "99: fzf-lua is required for this extension",
        vim.log.levels.ERROR
      )
      return
    end

    fzf.fzf_exec(promote_current(models, current), {
      prompt = "99: Select Model (current: " .. current .. ")> ",
      actions = {
        ["enter"] = function(selected)
          if not selected or #selected == 0 then
            return
          end
          pickers_util.on_model_selected(selected[1])
        end,
      },
    })
  end)
end

function M.select_provider()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify(
      "99: fzf-lua is required for this extension",
      vim.log.levels.ERROR
    )
    return
  end

  local info = pickers_util.get_providers()

  fzf.fzf_exec(promote_current(info.names, info.current), {
    prompt = "99: Select Provider (current: " .. info.current .. ")> ",
    actions = {
      ["enter"] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        pickers_util.on_provider_selected(selected[1], info.lookup)
      end,
    },
  })
end

return M
