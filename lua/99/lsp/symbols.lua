local formatter = require("99.lsp.formatter")

local M = {}

--- @class _99.Lsp.Symbol
--- @field name string Symbol name
--- @field kind number LSP SymbolKind value
--- @field signature string? Formatted type signature (populated by hover)
--- @field detail string? Additional detail from LSP
--- @field range { start: { line: number, character: number }, ["end"]: { line: number, character: number } }
--- @field selectionRange { start: { line: number, character: number }, ["end"]: { line: number, character: number } }?
--- @field children _99.Lsp.Symbol[]?
--- @field containerName string? For SymbolInformation (flat) responses

--- Parse a DocumentSymbol response into our internal Symbol format
--- @param doc_symbol table LSP DocumentSymbol
--- @return _99.Lsp.Symbol
local function parse_document_symbol(doc_symbol)
    local symbol = {
        name = doc_symbol.name,
        kind = doc_symbol.kind,
        detail = doc_symbol.detail,
        range = doc_symbol.range,
        selectionRange = doc_symbol.selectionRange,
        children = nil,
        signature = nil,
    }

    -- Build a basic signature from name and detail
    if doc_symbol.detail and doc_symbol.detail ~= "" then
        symbol.signature = doc_symbol.name .. ": " .. doc_symbol.detail
    else
        symbol.signature = doc_symbol.name
    end

    -- Recursively parse children
    if doc_symbol.children and #doc_symbol.children > 0 then
        symbol.children = {}
        for _, child in ipairs(doc_symbol.children) do
            table.insert(symbol.children, parse_document_symbol(child))
        end
    end

    return symbol
end

--- Parse a SymbolInformation response (flat list) into Symbol format
--- @param symbol_info table LSP SymbolInformation
--- @return _99.Lsp.Symbol
local function parse_symbol_information(symbol_info)
    -- SymbolInformation has location instead of range
    local range = symbol_info.location and symbol_info.location.range

    return {
        name = symbol_info.name,
        kind = symbol_info.kind,
        detail = nil,
        range = range,
        selectionRange = nil,
        children = nil,
        containerName = symbol_info.containerName,
        signature = symbol_info.name,
    }
end

--- Check if the response is in DocumentSymbol format (hierarchical)
--- @param result table LSP response
--- @return boolean
local function is_document_symbol_response(result)
    if not result or #result == 0 then
        return false
    end
    -- DocumentSymbol has 'range' and 'selectionRange', SymbolInformation has 'location'
    return result[1].range ~= nil and result[1].selectionRange ~= nil
end

--- Parse LSP symbol response (handles both DocumentSymbol[] and SymbolInformation[])
--- @param result table LSP response
--- @return _99.Lsp.Symbol[]
function M.parse_symbol_response(result)
    if not result or #result == 0 then
        return {}
    end

    local symbols = {}

    if is_document_symbol_response(result) then
        -- Hierarchical DocumentSymbol format
        for _, doc_symbol in ipairs(result) do
            table.insert(symbols, parse_document_symbol(doc_symbol))
        end
    else
        -- Flat SymbolInformation format
        for _, symbol_info in ipairs(result) do
            table.insert(symbols, parse_symbol_information(symbol_info))
        end
    end

    return symbols
end

--- Make a textDocument/documentSymbol request to the LSP server
--- @param bufnr number Buffer number
--- @param callback fun(symbols: _99.Lsp.Symbol[]?, err: string?) Callback with parsed symbols
function M.get_document_symbols(bufnr, callback)
    local lsp = require("99.lsp")

    -- Check if LSP is available
    if not lsp.is_available(bufnr) then
        callback(nil, "no_lsp_client")
        return
    end

    -- Build request params
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
    }

    -- Make the request
    vim.lsp.buf_request(
        bufnr,
        "textDocument/documentSymbol",
        params,
        function(err, result, ctx, _)
            if err then
                callback(nil, vim.inspect(err))
                return
            end

            if not result then
                callback({}, nil)
                return
            end

            -- Parse the response
            local symbols = M.parse_symbol_response(result)
            callback(symbols, nil)
        end
    )
end

--- Filter symbols by kind
--- @param symbols _99.Lsp.Symbol[] Symbols to filter
--- @param include_kinds number[]? Symbol kinds to include (nil = all)
--- @param exclude_kinds number[]? Symbol kinds to exclude (nil = none)
--- @return _99.Lsp.Symbol[] Filtered symbols
function M.filter_symbols(symbols, include_kinds, exclude_kinds)
    local result = {}

    local include_set = nil
    if include_kinds and #include_kinds > 0 then
        include_set = {}
        for _, kind in ipairs(include_kinds) do
            include_set[kind] = true
        end
    end

    local exclude_set = {}
    if exclude_kinds and #exclude_kinds > 0 then
        for _, kind in ipairs(exclude_kinds) do
            exclude_set[kind] = true
        end
    end

    for _, symbol in ipairs(symbols) do
        local include = true

        -- Check include filter
        if include_set and not include_set[symbol.kind] then
            include = false
        end

        -- Check exclude filter
        if exclude_set[symbol.kind] then
            include = false
        end

        if include then
            -- Deep copy and filter children recursively
            local filtered_symbol = vim.tbl_extend("force", {}, symbol)
            if symbol.children and #symbol.children > 0 then
                filtered_symbol.children = M.filter_symbols(symbol.children, include_kinds, exclude_kinds)
            end
            table.insert(result, filtered_symbol)
        end
    end

    return result
end

--- Limit the number of symbols (truncate to top-level if too many)
--- @param symbols _99.Lsp.Symbol[] Symbols to limit
--- @param max_symbols number Maximum symbols to return
--- @return _99.Lsp.Symbol[] Limited symbols
function M.limit_symbols(symbols, max_symbols)
    if #symbols <= max_symbols then
        return symbols
    end

    -- Count total symbols (including children)
    local function count_symbols(syms)
        local count = #syms
        for _, sym in ipairs(syms) do
            if sym.children then
                count = count + count_symbols(sym.children)
            end
        end
        return count
    end

    local total = count_symbols(symbols)
    if total <= max_symbols then
        return symbols
    end

    -- If too many, return only top-level symbols without children
    local result = {}
    for i, symbol in ipairs(symbols) do
        if i > max_symbols then
            break
        end
        local limited = vim.tbl_extend("force", {}, symbol)
        limited.children = nil -- Remove children to reduce count
        table.insert(result, limited)
    end

    return result
end

--- Get the position for hover request (start of selection range or range)
--- @param symbol _99.Lsp.Symbol
--- @return { line: number, character: number }
function M.get_symbol_position(symbol)
    if symbol.selectionRange then
        return symbol.selectionRange.start
    end
    return symbol.range.start
end

return M
