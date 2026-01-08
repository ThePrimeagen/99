local M = {}

local async = require("99.lsp.async")

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

    if doc_symbol.detail and doc_symbol.detail ~= "" then
        symbol.signature = doc_symbol.name .. ": " .. doc_symbol.detail
    else
        symbol.signature = doc_symbol.name
    end

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
    return result[1].range ~= nil and result[1].selectionRange ~= nil
end

--- Strip markdown code fences from text (local helper)
--- @param text string Text with potential markdown fences
--- @return string Clean text
local function strip_fences(text)
    local result = text:gsub("```%w*\n?", "")
    result = result:gsub("```", "")
    result = result:gsub("^%s+", ""):gsub("%s+$", "")
    return result
end

--- Extract text content from hover response contents
--- LSP hover contents can be: string, MarkupContent, or MarkedString[]
--- @param contents any The contents field from hover response
--- @return string Extracted text (markdown fences stripped)
function M.parse_hover_contents(contents)
    if not contents then
        return ""
    end

    if type(contents) == "string" then
        return strip_fences(contents)
    end

    if type(contents) == "table" and contents.value then
        return strip_fences(contents.value)
    end

    if type(contents) == "table" and #contents > 0 then
        local parts = {}
        for _, part in ipairs(contents) do
            if type(part) == "string" then
                table.insert(parts, part)
            elseif type(part) == "table" and part.value then
                table.insert(parts, part.value)
            elseif type(part) == "table" and part.language then
                table.insert(parts, part.value or "")
            end
        end
        return strip_fences(table.concat(parts, "\n"))
    end

    return ""
end

--- Parse inlay hints response (LSP 3.17)
--- @param hints any[] LSP InlayHint[]
--- @return table[] Parsed hints
function M.parse_inlay_hints(hints)
    if not hints then
        return {}
    end

    local parsed = {}
    for _, hint in ipairs(hints) do
        local label = hint.label
        if type(label) == "table" then
            local parts = {}
            for _, part in ipairs(label) do
                table.insert(parts, part.value or "")
            end
            label = table.concat(parts, "")
        end

        table.insert(parsed, {
            position = hint.position,
            label = label,
            kind = hint.kind,
            paddingLeft = hint.paddingLeft,
            paddingRight = hint.paddingRight,
        })
    end

    return parsed
end

--- Get server capabilities for buffer
--- @param bufnr number Buffer number
--- @return table capabilities Server capabilities (empty table if none)
function M.get_server_capabilities(bufnr)
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    local client = clients[1]
    if client and client.server_capabilities then
        return client.server_capabilities
    end
    return {}
end

--- Make a raw LSP request (callback-based, for internal use)
--- @param bufnr number Buffer number
--- @param method string LSP method name
--- @param params table Request parameters
--- @param callback fun(result: any, err: string?)
local function lsp_request(bufnr, method, params, callback)
    vim.lsp.buf_request(bufnr, method, params, function(err, result, _, _)
        if err then
            callback(nil, vim.inspect(err))
        else
            callback(result, nil)
        end
    end)
end

--- Get document symbols for buffer
--- Must be called inside async.run()
--- @param bufnr number Buffer number
--- @return table[]? symbols DocumentSymbol[] or SymbolInformation[]
--- @return string? err Error message
function M.document_symbols(bufnr)
    return async.await(function(callback)
        local params = {
            textDocument = vim.lsp.util.make_text_document_params(bufnr),
        }
        lsp_request(bufnr, "textDocument/documentSymbol", params, callback)
    end)
end

--- Get hover information at position
--- Must be called inside async.run()
--- @param bufnr number Buffer number
--- @param position { line: number, character: number } LSP position (0-based)
--- @return table? hover Hover result
--- @return string? err Error message
function M.hover(bufnr, position)
    return async.await(function(callback)
        local params = {
            textDocument = vim.lsp.util.make_text_document_params(bufnr),
            position = position,
        }
        lsp_request(bufnr, "textDocument/hover", params, callback)
    end)
end

--- Get inlay hints for a range
--- Must be called inside async.run()
--- @param bufnr number Buffer number
--- @param range { start: table, ["end"]: table }? Range (nil = full buffer)
--- @return table[]? hints Parsed InlayHint[]
--- @return string? err Error message
function M.inlay_hints(bufnr, range)
    if not range then
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = line_count, character = 0 },
        }
    end

    local result, err = async.await(function(callback)
        local params = {
            textDocument = vim.lsp.util.make_text_document_params(bufnr),
            range = range,
        }
        lsp_request(bufnr, "textDocument/inlayHint", params, callback)
    end)

    if err then
        return nil, err
    end

    return M.parse_inlay_hints(result), nil
end

--- Batch hover requests for multiple positions
--- Must be called inside async.run()
--- @param bufnr number Buffer number
--- @param positions { line: number, character: number }[] Positions
--- @return table<number, table?> results Index -> hover result
function M.batch_hover(bufnr, positions)
    return async.parallel_map(positions, function(position)
        local result, _ = M.hover(bufnr, position)
        return result
    end)
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
        for _, doc_symbol in ipairs(result) do
            table.insert(symbols, parse_document_symbol(doc_symbol))
        end
    else
        for _, symbol_info in ipairs(result) do
            table.insert(symbols, parse_symbol_information(symbol_info))
        end
    end

    return symbols
end

--- Limit the number of symbols (truncate to top-level if too many)
--- @param symbols _99.Lsp.Symbol[] Symbols to limit
--- @param max_symbols number Maximum symbols to return
--- @return _99.Lsp.Symbol[] Limited symbols
function M.limit_symbols(symbols, max_symbols)
    if #symbols <= max_symbols then
        return symbols
    end

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

    local limited = {}
    for i, symbol in ipairs(symbols) do
        if i > max_symbols then
            break
        end
        local sym = vim.tbl_extend("force", {}, symbol)
        sym.children = nil
        table.insert(limited, sym)
    end

    return limited
end

return M
