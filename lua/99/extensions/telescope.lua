local pickers_util = require("99.extensions.pickers")

local M = {}

--- @param provider _99.Providers.BaseProvider?
function M.select_model(provider)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify(
      "99: telescope.nvim is required for this extension",
      vim.log.levels.ERROR
    )
    return
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers_util.get_models(provider, function(models, current)
    pickers
      .new({}, {
        prompt_title = "99: Select Model (current: " .. current .. ")",
        default_selection_index = pickers_util.index_of(models, current),
        finder = finders.new_table({ results = models }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end
            pickers_util.on_model_selected(selection[1])
          end)
          return true
        end,
      })
      :find()
  end)
end

function M.select_provider()
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify(
      "99: telescope.nvim is required for this extension",
      vim.log.levels.ERROR
    )
    return
  end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local info = pickers_util.get_providers()

  pickers
    .new({}, {
      prompt_title = "99: Select Provider (current: " .. info.current .. ")",
      default_selection_index = pickers_util.index_of(info.names, info.current),
      finder = finders.new_table({ results = info.names }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          pickers_util.on_provider_selected(selection[1], info.lookup)
        end)
        return true
      end,
    })
    :find()
end

return M
