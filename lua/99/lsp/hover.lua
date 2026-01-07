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

    -- Simple string
    if type(contents) == "string" then
        return contents
    end

    -- MarkupContent: { kind: "markdown"|"plaintext", value: string }
    if type(contents) == "table" and contents.value then
        return contents.value
    end

    -- MarkedString[] or MarkupContent[]
    if type(contents) == "table" and #contents > 0 then
        local parts = {}
        for _, part in ipairs(contents) do
            if type(part) == "string" then
                table.insert(parts, part)
            elseif type(part) == "table" and part.value then
                table.insert(parts, part.value)
            elseif type(part) == "table" and part.language then
                -- MarkedString: { language: string, value: string }
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
    -- Remove opening fences like ```lua, ```typescript, etc.
    local result = text:gsub("```%w*\n?", "")
    -- Remove closing fences
    result = result:gsub("```", "")
    -- Trim whitespace
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

    -- Handle Lua-style: "function foo(a: number, b: string): boolean"
    local lua_params, lua_ret = clean:match("function%s*[%w_%.%:]*%((.-)%)%s*:%s*([^\n]+)")
    if lua_params then
        return string.format("(%s): %s", lua_params, lua_ret)
    end

    -- Handle Lua function without return type
    local lua_params_only = clean:match("function%s*[%w_%.%:]*%((.-)%)")
    if lua_params_only then
        return string.format("(%s)", lua_params_only)
    end

    -- Handle TypeScript/JavaScript: "const foo: (a: number) => string"
    local ts_arrow = clean:match(":%s*(%(.-%)%s*=>%s*[^\n]+)")
    if ts_arrow then
        return ts_arrow
    end

    -- Handle TypeScript method: "method(a: number): string"
    local ts_method = clean:match("[%w_]+%(.-%)%s*:%s*[^\n]+")
    if ts_method then
        return ts_method
    end

    -- Handle simple type annotation: "foo: string"
    local simple_type = clean:match("^[%w_]+:%s*([^\n]+)")
    if simple_type then
        return simple_type
    end

    -- Handle "local foo: Type" style
    local local_type = clean:match("local%s+[%w_]+:%s*([^\n]+)")
    if local_type then
        return local_type
    end

    -- Return first line as fallback
    local first_line = clean:match("^([^\n]+)")
    return first_line or clean
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

    -- Check if hover is supported
    if not client.server_capabilities.hoverProvider then
        callback(nil, "hover_not_supported")
        return
    end

    local params = {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = position,
    }

    vim.lsp.buf_request(bufnr, "textDocument/hover", params, function(err, result, ctx, _)
        if err then
            callback(nil, vim.inspect(err))
            return
        end

        if not result or not result.contents then
            callback(nil, nil) -- No hover info available (not an error)
            return
        end

        local contents = extract_hover_contents(result.contents)
        callback({
            contents = contents,
            range = result.range,
        }, nil)
    end)
end

--- Batch hover requests for multiple positions
--- Useful for enriching multiple symbols efficiently
--- @param bufnr number Buffer number
--- @param positions { line: number, character: number }[] Array of positions
--- @param callback fun(results: table<number, _99.Lsp.HoverResult?>) Callback with index -> result map
function M.batch_hover(bufnr, positions, callback)
    if not positions or #positions == 0 then
        callback({})
        return
    end

    local results = {}
    local pending = #positions
    local completed = false

    -- Handle completion
    local function check_done()
        if completed then
            return
        end
        pending = pending - 1
        if pending == 0 then
            completed = true
            callback(results)
        end
    end

    -- Request hover for each position
    for i, position in ipairs(positions) do
        M.get_hover(bufnr, position, function(result, _)
            results[i] = result
            check_done()
        end)
    end
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

    -- Collect all positions (including children)
    local positions = {}
    local symbol_refs = {} -- Track which symbol each position belongs to

    local function collect_positions(syms, parent_path)
        for i, sym in ipairs(syms) do
            local path = parent_path .. "." .. i
            local pos = symbols_mod.get_symbol_position(sym)
            table.insert(positions, pos)
            table.insert(symbol_refs, { symbol = sym, path = path })

            -- Recursively collect children
            if sym.children and #sym.children > 0 then
                collect_positions(sym.children, path)
            end
        end
    end

    collect_positions(symbols, "root")

    -- Batch hover all positions
    M.batch_hover(bufnr, positions, function(results)
        -- Apply hover results to symbols
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
