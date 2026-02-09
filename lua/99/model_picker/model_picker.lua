local M = {}

--- @param res vim.SystemCompleted
--- @return table
local function extract_opencode_models(res)
  local models = {}

  for line in (res.stdout or ""):gmatch("[^\r\n]+") do
    if line ~= "" then
      table.insert(models, line)
    end
  end

  return models
end

function M.pick_opencode_model()
  vim.system({ "opencode", "models" }, { text = true }, function(res)
    if res.code ~= 0 then
      vim.schedule(function()
        vim.notify(
          ("opencode models failed (%d): %s"):format(res.code, res.stderr or ""),
          vim.log.levels.ERROR
        )
      end)
      return
    end

    local models = extract_opencode_models(res)

    vim.schedule(function()
      local pickers = require("telescope.pickers")
      local finders = require("telescope.finders")
      local sorters = require("telescope.sorters")
      local actions = require("telescope.actions")
      local action_state = require("telescope.actions.state")

      pickers
        .new({}, {
          prompt_title = "99: Select model",
          finder = finders.new_table({
            results = models,
          }),
          sorter = sorters.get_generic_fuzzy_sorter(),
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              local entry = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              local model = entry and (entry.value or entry[1])
              if not model or model == "" then
                return
              end
              require("99").set_model(model)
              vim.notify("99 model set to: " .. model)
            end)
            return true
          end,
        })
        :find()
    end)
  end)
end

return M
