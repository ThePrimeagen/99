local M = {}

M.names = {
    body = "compound_statement",
}

--- @param item_name string
--- @return string
function M.log_item(item_name)
    return string.format('printf("%%p\\n", (void*)&%s);', item_name)
end

return M
