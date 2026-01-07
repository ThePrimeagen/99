local M = {}

--- Find symbols (identifiers) used within a specific range of a buffer
--- @param bufnr number Buffer number
--- @param range _99.Range? Range to search within (nil = entire buffer)
--- @return string[] Symbol names used in the range
function M.find_used_symbols(bufnr, range)
    local lines
    if range then
        local start_row, _ = range.start:to_vim()
        local end_row, _ = range.end_:to_vim()
        lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    else
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end

    local content = table.concat(lines, "\n")
    local symbols = {}
    local seen = {}

    for identifier in content:gmatch("[%a_][%w_]*") do
        if
            not seen[identifier]
            and #identifier > 1
            and not M.is_keyword(identifier)
        then
            seen[identifier] = true
            table.insert(symbols, identifier)
        end
    end

    return symbols
end

--- Common keywords to exclude from symbol detection
--- @type table<string, boolean>
local KEYWORDS = {
    -- Lua keywords
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["goto"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
    -- TypeScript/JavaScript keywords
    ["const"] = true,
    ["let"] = true,
    ["var"] = true,
    ["class"] = true,
    ["extends"] = true,
    ["implements"] = true,
    ["interface"] = true,
    ["type"] = true,
    ["import"] = true,
    ["export"] = true,
    ["from"] = true,
    ["async"] = true,
    ["await"] = true,
    ["new"] = true,
    ["this"] = true,
    ["super"] = true,
    ["typeof"] = true,
    ["instanceof"] = true,
    ["void"] = true,
    ["null"] = true,
    ["undefined"] = true,
    -- Python keywords
    ["def"] = true,
    ["self"] = true,
    ["cls"] = true,
    ["pass"] = true,
    ["raise"] = true,
    ["try"] = true,
    ["except"] = true,
    ["finally"] = true,
    ["with"] = true,
    ["as"] = true,
    ["lambda"] = true,
    ["yield"] = true,
    ["global"] = true,
    ["nonlocal"] = true,
    -- Go keywords
    ["package"] = true,
    ["func"] = true,
    ["defer"] = true,
    ["go"] = true,
    ["chan"] = true,
    ["select"] = true,
    ["case"] = true,
    ["default"] = true,
    ["switch"] = true,
    ["fallthrough"] = true,
    ["range"] = true,
    ["struct"] = true,
    ["map"] = true,
}

--- Check if an identifier is a common keyword
--- @param identifier string
--- @return boolean
function M.is_keyword(identifier)
    return KEYWORDS[identifier] == true
end

--- Filter imports to only those containing symbols actually used
--- @param imports _99.Lsp.Import[] All imports
--- @param used_symbols string[] Symbols used in the current context
--- @return _99.Lsp.Import[] Filtered imports
function M.filter_relevant_imports(imports, used_symbols)
    if not imports or #imports == 0 then
        return {}
    end

    if not used_symbols or #used_symbols == 0 then
        return imports
    end

    local used_set = {}
    for _, sym in ipairs(used_symbols) do
        used_set[sym] = true
    end

    local relevant = {}
    for _, import in ipairs(imports) do
        local is_relevant = false

        for _, sym_name in ipairs(import.symbols or {}) do
            if used_set[sym_name] then
                is_relevant = true
                break
            end
        end

        if not is_relevant and import.resolved_symbols then
            for _, sym in ipairs(import.resolved_symbols) do
                if used_set[sym.name] then
                    is_relevant = true
                    break
                end
            end
        end

        if is_relevant then
            table.insert(relevant, import)
        end
    end

    return relevant
end

--- Filter symbols to only those used in a range
--- @param symbols _99.Lsp.Symbol[] All symbols
--- @param used_symbols string[] Symbols used in the current context
--- @return _99.Lsp.Symbol[] Filtered symbols
function M.filter_relevant_symbols(symbols, used_symbols)
    if not symbols or #symbols == 0 then
        return {}
    end

    if not used_symbols or #used_symbols == 0 then
        return symbols
    end

    local used_set = {}
    for _, sym in ipairs(used_symbols) do
        used_set[sym] = true
    end

    local relevant = {}
    for _, symbol in ipairs(symbols) do
        if used_set[symbol.name] then
            table.insert(relevant, symbol)
        elseif symbol.children then
            local relevant_children =
                M.filter_relevant_symbols(symbol.children, used_symbols)
            if #relevant_children > 0 then
                local filtered_symbol = vim.tbl_extend("force", {}, symbol)
                filtered_symbol.children = relevant_children
                table.insert(relevant, filtered_symbol)
            end
        end
    end

    return relevant
end

--- Calculate relevance score for an import based on symbol usage
--- @param import _99.Lsp.Import Import to score
--- @param used_symbols string[] Symbols used in current context
--- @return number Score (higher = more relevant)
function M.calculate_import_relevance(import, used_symbols)
    if not used_symbols or #used_symbols == 0 then
        return 0
    end

    local used_set = {}
    for _, sym in ipairs(used_symbols) do
        used_set[sym] = true
    end

    local score = 0
    for _, sym_name in ipairs(import.symbols or {}) do
        if used_set[sym_name] then
            score = score + 10
        end
    end

    if import.resolved_symbols then
        for _, sym in ipairs(import.resolved_symbols) do
            if used_set[sym.name] then
                score = score + 5
            end
        end
    end

    return score
end

--- Sort imports by relevance score
--- @param imports _99.Lsp.Import[] Imports to sort
--- @param used_symbols string[] Symbols used in current context
--- @return _99.Lsp.Import[] Sorted imports (most relevant first)
function M.sort_imports_by_relevance(imports, used_symbols)
    if not imports or #imports == 0 then
        return {}
    end

    local scored = {}
    for _, import in ipairs(imports) do
        table.insert(scored, {
            import = import,
            score = M.calculate_import_relevance(import, used_symbols),
        })
    end

    table.sort(scored, function(a, b)
        return a.score > b.score
    end)

    local sorted = {}
    for _, item in ipairs(scored) do
        table.insert(sorted, item.import)
    end

    return sorted
end

--- Get used symbols from a range using treesitter if available
--- Falls back to regex-based extraction if treesitter unavailable
--- @param bufnr number Buffer number
--- @param range _99.Range? Range to search within
--- @return string[] Symbol names
function M.find_used_symbols_smart(bufnr, range)
    local filetype = vim.bo[bufnr].filetype

    local ok, ts_parser = pcall(vim.treesitter.get_parser, bufnr, filetype)
    if ok and ts_parser then
        return M._find_symbols_with_treesitter(bufnr, range, ts_parser)
    end

    return M.find_used_symbols(bufnr, range)
end

--- Find symbols using treesitter
--- @param bufnr number Buffer number
--- @param range _99.Range? Range to search
--- @param parser vim.treesitter.LanguageTree Treesitter parser
--- @return string[]
function M._find_symbols_with_treesitter(bufnr, range, parser)
    local tree = parser:parse()[1]
    if not tree then
        return M.find_used_symbols(bufnr, range)
    end

    local root = tree:root()
    local symbols = {}
    local seen = {}

    local query_str = "(identifier) @id"
    local ok, query =
        pcall(vim.treesitter.query.parse, parser:lang(), query_str)
    if not ok then
        return M.find_used_symbols(bufnr, range)
    end

    local start_row, end_row = 0, -1
    if range then
        start_row, _ = range.start:to_vim()
        end_row, _ = range.end_:to_vim()
    end

    for id, node, _ in query:iter_captures(root, bufnr, start_row, end_row) do
        local name = query.captures[id]
        if name == "id" then
            local text = vim.treesitter.get_node_text(node, bufnr)
            if text and not seen[text] and not M.is_keyword(text) then
                seen[text] = true
                table.insert(symbols, text)
            end
        end
    end

    return symbols
end

return M
