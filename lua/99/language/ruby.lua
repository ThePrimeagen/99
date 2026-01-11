local M = {}

M.names = {
    body = "body_statement",
    block_body = "block_body",
}

--- @param item_name string
--- @return string
function M.log_item(item_name)
    return string.format("puts %s.inspect", item_name)
end

return M
