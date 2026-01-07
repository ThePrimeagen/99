local M = {}

--- Build complete LSP context for a RequestContext
--- Gathers symbols from current file and optionally resolves imports
--- @param request_context _99.RequestContext The request context
--- @param callback fun(result: string?, err: string?) Callback with formatted context
function M.build_context(request_context, callback)
    local lsp = require("99.lsp")
    local symbols = require("99.lsp.symbols")
    local hover = require("99.lsp.hover")
    local imports = require("99.lsp.imports")
    local formatter = require("99.lsp.formatter")

    local bufnr = request_context.buffer
    local config = lsp.config
    local logger = request_context.logger:clone():set_area("lsp.context")

    if not lsp.is_available(bufnr) then
        logger:debug("LSP not available for buffer", "bufnr", bufnr)
        callback(nil, "lsp_not_available")
        return
    end

    logger:debug("Building LSP context", "bufnr", bufnr, "config", config)

    imports.reset_visited()
    local uri = lsp.buf_to_uri(bufnr)
    imports.mark_visited(uri)

    symbols.get_document_symbols(bufnr, function(doc_symbols, sym_err)
        if sym_err then
            logger:debug("Failed to get document symbols", "err", sym_err)
            callback(nil, sym_err)
            return
        end

        if not doc_symbols or #doc_symbols == 0 then
            logger:debug("No symbols found")
            callback(nil, nil)
            return
        end

        doc_symbols = symbols.limit_symbols(doc_symbols, config.max_symbols)
        hover.enrich_symbols(bufnr, doc_symbols, function(enriched_symbols)
            if config.import_depth > 0 then
                imports.get_imports(bufnr, true, function(resolved_imports)
                    local valid_imports = {}
                    for _, imp in ipairs(resolved_imports or {}) do
                        if not imp.is_external and imp.resolved_uri and not imports.is_visited(imp.resolved_uri) then
                            imports.mark_visited(imp.resolved_uri)
                            table.insert(valid_imports, imp)
                        end
                    end

                    M._enrich_import_symbols(bufnr, valid_imports, function(enriched_imports)
                        local result = M._format_complete_context(
                            request_context.full_path,
                            enriched_symbols,
                            enriched_imports
                        )
                        logger:debug("Built LSP context", "length", #result)
                        callback(result, nil)
                    end)
                end)
            else
                local result = formatter.format_file_context(
                    request_context.full_path,
                    enriched_symbols
                )
                logger:debug("Built LSP context (no imports)", "length", #result)
                callback(result, nil)
            end
        end)
    end)
end

--- Enrich imported symbols with hover information
--- @param source_bufnr number Source buffer (for LSP client)
--- @param resolved_imports _99.Lsp.Import[] Resolved imports
--- @param callback fun(imports: _99.Lsp.Import[])
function M._enrich_import_symbols(source_bufnr, resolved_imports, callback)
    if not resolved_imports or #resolved_imports == 0 then
        callback({})
        return
    end

    local hover = require("99.lsp.hover")
    local definitions = require("99.lsp.definitions")
    local pending = #resolved_imports
    local completed = 0

    local function check_done()
        completed = completed + 1
        if completed >= pending then
            callback(resolved_imports)
        end
    end

    for _, imp in ipairs(resolved_imports) do
        if imp.resolved_symbols and #imp.resolved_symbols > 0 and imp.resolved_uri then
            local file_path = vim.uri_to_fname(imp.resolved_uri)
            definitions.ensure_buffer_loaded(file_path, function(target_bufnr, err)
                if err or not target_bufnr then
                    check_done()
                    return
                end

                hover.enrich_symbols(target_bufnr, imp.resolved_symbols, function(enriched)
                    imp.resolved_symbols = enriched
                    check_done()
                end)
            end)
        else
            check_done()
        end
    end
end

--- Format the complete context including imports
--- @param file_path string Current file path
--- @param symbols _99.Lsp.Symbol[] Current file symbols
--- @param resolved_imports _99.Lsp.Import[] Resolved imports
--- @return string Formatted context
function M._format_complete_context(file_path, symbols, resolved_imports)
    local formatter = require("99.lsp.formatter")
    local parts = {}

    local file_context = formatter.format_file_context(file_path, symbols)
    table.insert(parts, file_context)

    if resolved_imports and #resolved_imports > 0 then
        local import_context = formatter.format_imports(resolved_imports)
        if import_context and import_context ~= "" then
            table.insert(parts, import_context)
        end
    end

    return table.concat(parts, "\n")
end

--- Build context with timeout protection
--- @param request_context _99.RequestContext
--- @param timeout_ms number Timeout in milliseconds
--- @param callback fun(result: string?, err: string?)
function M.build_context_with_timeout(request_context, timeout_ms, callback)
    local completed = false
    local timer = vim.uv.new_timer()

    timer:start(timeout_ms, 0, vim.schedule_wrap(function()
        if not completed then
            completed = true
            timer:stop()
            timer:close()
            callback(nil, "timeout")
        end
    end))

    M.build_context(request_context, function(result, err)
        if completed then
            return
        end

        completed = true
        timer:stop()
        timer:close()
        callback(result, err)
    end)
end

return M
