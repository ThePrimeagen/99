--- @enum _99.Observers.Operation
local Operation = {
  REFACTOR = "refactor",
  FILL_IN_FUNCTION = "fill_in_function",
  VISUAL = "visual",
}

--- @class _99.Observers.ChangeInfo
--- @field context _99.RequestContext
--- @field buffer number? optional, overrides context.buffer for multi-file operations
--- @field start_line number
--- @field operation _99.Observers.Operation
--- @field prompt string?

--- @alias _99.Observers.OnChange fun(change_info: _99.Observers.ChangeInfo): nil

local M = {
  --- @type _99.Observers.OnChange[]
  on_change = {},
  Operation = Operation,
}

--- @param callback _99.Observers.OnChange
function M.register_on_change(callback)
  table.insert(M.on_change, callback)
end

--- @param change_info _99.Observers.ChangeInfo
function M.emit_change(change_info)
  for _, callback in ipairs(M.on_change) do
    callback(change_info)
  end
end

function M.clear()
  M.on_change = {}
end

--- Built-in observer: adds changes to quickfix list
--- This probably doesn't belong here but here we are for now
--- @param change_info _99.Observers.ChangeInfo
function M.add_to_quickfix(change_info)
  local description = change_info.prompt or change_info.operation
  if #description > 50 then
    description = description:sub(1, 47) .. "..."
  end

  vim.fn.setqflist({
    {
      bufnr = change_info.buffer or change_info.context.buffer,
      lnum = change_info.start_line,
      col = 0,
      text = description,
    },
  }, "a")
end

return M
