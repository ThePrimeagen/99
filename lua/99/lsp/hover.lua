local M = {}

--- @class _99.Lsp.HoverResult
--- @field contents string Extracted content from hover
--- @field range { start: { line: number, character: number }, ["end"]: { line: number, character: number } }?

--- Extract text content from hover response contents
--- LSP hover contents can be: string, MarkupContent, or MarkedString[]
--- @param contents any The contents field from hover response
--- @return string Extracted text
local function extract_hover_contents(contents)
    if not contents then
        return ""
    end

    if type(contents) == "string" then
        return contents
    end

    if type(contents) == "table" and contents.value then
        return contents.value
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
        return table.concat(parts, "\n")
    end

    return ""
end

--- Strip markdown code fences from hover text
--- @param text string Text with potential markdown fences
--- @return string Clean text
local function strip_markdown_fences(text)
    local result = text:gsub("```%w*\n?", "")
    result = result:gsub("```", "")
    result = result:gsub("^%s+", ""):gsub("%s+$", "")
    return result
end

--- Extract type signature from hover text
--- Handles various language formats and converts to compact TypeScript-style
--- @param hover_text string Raw hover text (may include markdown)
--- @return string Compact type signature
function M.extract_type_signature(hover_text)
    if not hover_text or hover_text == "" then
        return ""
    end

    local clean = strip_markdown_fences(hover_text)

    local lua_params, lua_ret =
        clean:match("function%s*[%w_%.%:]*%((.-)%)%s*:%s*([^\n]+)")
    if lua_params then
        return string.format("(%s): %s", lua_params, lua_ret)
    end

    local lua_params_only = clean:match("function%s*[%w_%.%:]*%((.-)%)")
    if lua_params_only then
        return string.format("(%s)", lua_params_only)
    end

    local ts_arrow = clean:match(":%s*(%(.-%)%s*=>%s*[^\n]+)")
    if ts_arrow then
        return ts_arrow
    end

    local ts_method = clean:match("[%w_]+%(.-%)%s*:%s*[^\n]+")
    if ts_method then
        return ts_method
    end

    local simple_type = clean:match("^[%w_]+:%s*([^\n]+)")
    if simple_type then
        return simple_type
    end

    local local_type = clean:match("local%s+[%w_]+:%s*([^\n]+)")
    if local_type then
        return local_type
    end

    local first_line = clean:match("^([^\n]+)")
    return first_line or clean
end

--- Extract minimal type info, stripping implementation details
--- Use this when you want just the type, not the full signature
--- @param hover_text string Raw hover text
--- @return string Minimal type
function M.extract_minimal_type(hover_text)
    if not hover_text or hover_text == "" then
        return ""
    end

    local clean = strip_markdown_fences(hover_text)

    local func_sig = clean:match("^(function[^\n]+)")
        or clean:match("^(local function[^\n]+)")
    if func_sig then
        func_sig = func_sig:gsub("%s*%-%-.*$", "")
        return func_sig
    end

    local ts_type = clean:match("^[%w_]+:%s*([^\n=]+)")
    if ts_type then
        return ts_type:gsub("%s+$", "")
    end

    local class_decl = clean:match("^(class%s+[%w_]+[^\n{]*)")
        or clean:match("^(interface%s+[%w_]+[^\n{]*)")
    if class_decl then
        return class_decl
    end

    local type_alias = clean:match("^(type%s+[%w_]+%s*=%s*[^\n]+)")
    if type_alias then
        return type_alias
    end

    local first_line = clean:match("^([^\n]+)")
    if first_line and #first_line > 100 then
        return first_line:sub(1, 97) .. "..."
    end
    return first_line or ""
end

--- Extract type for external package context
--- Provides a compact type representation suitable for AI context
--- @param hover_text string Raw hover text
--- @return string Type for external context
function M.extract_type_for_external(hover_text)
    if not hover_text or hover_text == "" then
        return ""
    end

    local clean = strip_markdown_fences(hover_text)

    local params, ret =
        clean:match("function%s*[%w_%.%:]*%((.-)%)%s*:%s*([^%s\n]+)")
    if params and ret then
        params = params:gsub("%s*=%s*[^,)]+", "")
        return string.format("(%s) => %s", params, ret)
    end

    local params_only = clean:match("function%s*[%w_%.%:]*%((.-)%)")
    if params_only then
        params_only = params_only:gsub("%s*=%s*[^,)]+", "")
        return string.format("(%s) => void", params_only)
    end

    local ts_arrow = clean:match("%((.-)%)%s*=>%s*([^\n]+)")
    if ts_arrow then
        return clean:match("%(.-%)%s*=>%s*[^\n]+")
    end

    local simple_type = clean:match(":%s*([^\n=]+)")
    if simple_type then
        return simple_type:gsub("%s+$", "")
    end

    if clean:match("^class%s") then
        local class_name = clean:match("^class%s+([%w_]+)")
        return class_name and ("class " .. class_name) or "class"
    end

    if clean:match("^interface%s") then
        local iface_name = clean:match("^interface%s+([%w_]+)")
        return iface_name and ("interface " .. iface_name) or "interface"
    end

    return M.extract_minimal_type(hover_text)
end

--- Make a textDocument/hover request for a specific position
--- @param bufnr number Buffer number
--- @param position { line: number, character: number } LSP position (0-based)
--- @param callback fun(result: _99.Lsp.HoverResult?, err: string?) Callback
function M.get_hover(bufnr, position, callback)
    local lsp = require("99.lsp")

    local client = lsp.get_client(bufnr)
    if not client then
        callback(nil, "no_lsp_client")
        return
    end

    if
        not client.server_capabilities
        or not client.server_capabilities.hoverProvider
    then
        callback(nil, "hover_not_supported")
        return
    end

    local params = {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = position,
    }

    vim.lsp.buf_request(
        bufnr,
        "textDocument/hover",
        params,
        function(err, result, _, _)
            if err then
                callback(nil, vim.inspect(err))
                return
            end

            if not result or not result.contents then
                callback(nil, nil)
                return
            end

            local contents = extract_hover_contents(result.contents)
            callback({
                contents = contents,
                range = result.range,
            }, nil)
        end
    )
end

--- Batch hover requests for multiple positions
--- Useful for enriching multiple symbols efficiently
--- @param bufnr number Buffer number
--- @param positions { line: number, character: number }[] Array of positions
--- @param callback fun(results: table<number, _99.Lsp.HoverResult?>) Callback with index -> result map
--- @return _99.Lsp.ParallelController? controller Control object for cancellation
function M.batch_hover(bufnr, positions, callback)
    local parallel = require("99.lsp.parallel")

    return parallel.parallel_map(positions, function(position, _, done)
        M.get_hover(bufnr, position, function(result, err)
            done(result, err)
        end)
    end, callback)
end

--- Batch hover requests with timeout
--- @param bufnr number Buffer number
--- @param positions { line: number, character: number }[] Array of positions
--- @param timeout_ms number Timeout in milliseconds
--- @param callback fun(results: table<number, _99.Lsp.HoverResult?>, timed_out: boolean)
--- @return _99.Lsp.ParallelController? controller
function M.batch_hover_with_timeout(bufnr, positions, timeout_ms, callback)
    local parallel = require("99.lsp.parallel")

    return parallel.parallel_map_with_timeout(
        positions,
        function(position, _, done)
            M.get_hover(bufnr, position, function(result, err)
                done(result, err)
            end)
        end,
        timeout_ms,
        callback
    )
end

--- Enrich a symbol with hover information
--- @param bufnr number Buffer number
--- @param symbol _99.Lsp.Symbol Symbol to enrich
--- @param callback fun(enriched: _99.Lsp.Symbol) Callback with enriched symbol
function M.enrich_symbol(bufnr, symbol, callback)
    local symbols_mod = require("99.lsp.symbols")
    local position = symbols_mod.get_symbol_position(symbol)

    M.get_hover(bufnr, position, function(result, _)
        if result and result.contents then
            local signature = M.extract_type_signature(result.contents)
            if signature and signature ~= "" then
                symbol.signature = signature
            end
        end
        callback(symbol)
    end)
end

--- Enrich multiple symbols with hover information
--- @param bufnr number Buffer number
--- @param symbols _99.Lsp.Symbol[] Symbols to enrich
--- @param callback fun(enriched: _99.Lsp.Symbol[]) Callback with enriched symbols
function M.enrich_symbols(bufnr, symbols, callback)
    if not symbols or #symbols == 0 then
        callback({})
        return
    end

    local symbols_mod = require("99.lsp.symbols")

    local positions = {}
    local symbol_refs = {}

    local function collect_positions(syms, parent_path)
        for i, sym in ipairs(syms) do
            local path = parent_path .. "." .. i
            local pos = symbols_mod.get_symbol_position(sym)
            table.insert(positions, pos)
            table.insert(symbol_refs, { symbol = sym, path = path })

            if sym.children and #sym.children > 0 then
                collect_positions(sym.children, path)
            end
        end
    end

    collect_positions(symbols, "root")

    M.batch_hover(bufnr, positions, function(results)
        for i, result in pairs(results) do
            if result and result.contents then
                local ref = symbol_refs[i]
                if ref then
                    local signature = M.extract_type_signature(result.contents)
                    if signature and signature ~= "" then
                        ref.symbol.signature = signature
                    end
                end
            end
        end

        callback(symbols)
    end)
end

return M
