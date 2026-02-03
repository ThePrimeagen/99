local M = {}

M.names = {}

--- @param item_name string
--- @return string
function M.log_item(item_name)
  return string.format("console.log(%s)", item_name)
end

return M
