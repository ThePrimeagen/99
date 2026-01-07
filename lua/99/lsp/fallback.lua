local M = {}

--- Symbol kinds for treesitter nodes (matching LSP SymbolKind where possible)
local TS_SYMBOL_KINDS = {
    ["function"] = 12,
    ["function_declaration"] = 12,
    ["function_definition"] = 12,
    ["method"] = 6,
    ["method_declaration"] = 6,
    ["method_definition"] = 6,
    ["class"] = 5,
    ["class_declaration"] = 5,
    ["class_definition"] = 5,
    ["interface"] = 11,
    ["interface_declaration"] = 11,
    ["type_alias"] = 26,
    ["type_alias_declaration"] = 26,
    ["enum"] = 10,
    ["enum_declaration"] = 10,
    ["struct"] = 23,
    ["struct_declaration"] = 23,
    ["module"] = 2,
    ["module_declaration"] = 2,
    ["variable_declaration"] = 13,
    ["lexical_declaration"] = 13,
    ["const_declaration"] = 14,
    ["field"] = 8,
    ["field_declaration"] = 8,
    ["property"] = 7,
    ["property_declaration"] = 7,
}

--- Node types to extract for each language
local EXTRACTABLE_TYPES = {
    lua = {
        "function_declaration",
        "function_definition",
        "local_function",
        "variable_list",
    },
    typescript = {
        "function_declaration",
        "method_definition",
        "class_declaration",
        "interface_declaration",
        "type_alias_declaration",
        "enum_declaration",
        "lexical_declaration",
    },
    typescriptreact = {
        "function_declaration",
        "method_definition",
        "class_declaration",
        "interface_declaration",
        "type_alias_declaration",
        "enum_declaration",
        "lexical_declaration",
    },
    javascript = {
        "function_declaration",
        "method_definition",
        "class_declaration",
        "lexical_declaration",
    },
    python = {
        "function_definition",
        "class_definition",
        "decorated_definition",
    },
    go = {
        "function_declaration",
        "method_declaration",
        "type_declaration",
        "const_declaration",
        "var_declaration",
    },
    rust = {
        "function_item",
        "impl_item",
        "struct_item",
        "enum_item",
        "trait_item",
        "type_item",
    },
}

--- Check if treesitter is available for buffer
--- @param bufnr number Buffer number
--- @return boolean
function M.is_available(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    return ok and parser ~= nil
end

--- Get the name from a treesitter node
--- @param node any Treesitter node
--- @param bufnr number Buffer number
--- @return string?
local function get_node_name(node, bufnr)
    local node_type = node:type()

    local name_node = node:field("name")[1]
    if name_node then
        return vim.treesitter.get_node_text(name_node, bufnr)
    end

    local declarator = node:field("declarator")[1]
    if declarator then
        local decl_name = declarator:field("name")[1]
        if decl_name then
            return vim.treesitter.get_node_text(decl_name, bufnr)
        end
    end

    for child in node:iter_children() do
        if child:type() == "identifier" or child:type() == "property_identifier" then
            return vim.treesitter.get_node_text(child, bufnr)
        end
    end

    return nil
end

--- Convert a treesitter node to a symbol structure
--- @param node any Treesitter node
--- @param bufnr number Buffer number
--- @return _99.Lsp.Symbol?
local function node_to_symbol(node, bufnr)
    local node_type = node:type()
    local name = get_node_name(node, bufnr)

    if not name then
        return nil
    end

    local start_row, start_col, end_row, end_col = node:range()

    local kind = TS_SYMBOL_KINDS[node_type] or 13

    return {
        name = name,
        kind = kind,
        range = {
            start = { line = start_row, character = start_col },
            ["end"] = { line = end_row, character = end_col },
        },
        children = nil,
        signature = nil,
    }
end

--- Extract symbols from buffer using treesitter
--- @param bufnr number Buffer number
--- @return _99.Lsp.Symbol[]
function M.get_symbols(bufnr)
    if not M.is_available(bufnr) then
        return {}
    end

    local ft = vim.bo[bufnr].filetype
    local types_to_extract = EXTRACTABLE_TYPES[ft]

    if not types_to_extract then
        types_to_extract = {
            "function_declaration",
            "function_definition",
            "method_definition",
            "class_declaration",
            "class_definition",
        }
    end

    local symbols = {}
    local parser = vim.treesitter.get_parser(bufnr)
    local tree = parser:parse()[1]

    if not tree then
        return {}
    end

    local root = tree:root()

    local type_set = {}
    for _, t in ipairs(types_to_extract) do
        type_set[t] = true
    end

    for child in root:iter_children() do
        local child_type = child:type()
        if type_set[child_type] then
            local symbol = node_to_symbol(child, bufnr)
            if symbol then
                table.insert(symbols, symbol)
            end
        end

        for grandchild in child:iter_children() do
            local gc_type = grandchild:type()
            if type_set[gc_type] then
                local symbol = node_to_symbol(grandchild, bufnr)
                if symbol then
                    table.insert(symbols, symbol)
                end
            end
        end
    end

    return symbols
end

--- Build treesitter-based context for a RequestContext
--- @param request_context _99.RequestContext
--- @param callback fun(result: string?, err: string?)
function M.get_treesitter_context(request_context, callback)
    local bufnr = request_context.buffer
    local formatter = require("99.lsp.formatter")

    if not M.is_available(bufnr) then
        callback(nil, "treesitter_not_available")
        return
    end

    local symbols = M.get_symbols(bufnr)

    if #symbols == 0 then
        callback(nil, nil)
        return
    end

    local result = formatter.format_file_context(request_context.full_path, symbols)
    callback(result, nil)
end

return M
