local M = {}

M.names = {}

--- @param item_name string
--- @return string
function M.log_item(item_name)
    return string.format('IO.inspect(%s, label: "%s")', item_name, item_name)
end

return M
