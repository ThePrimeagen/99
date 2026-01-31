local M = {}

M.names = {
  "99-function-signature",
  "99-struct",
}
--- @param item_name string
--- @return string
function M.log_item(item_name)
  return string.format('fmt.Printf("%%+v\\n", %s)', item_name)
end

return M
