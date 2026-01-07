local M = {}

--- @class _99.Lsp.ContextOptions
--- @field budget _99.Lsp.Budget? Token budget (nil = no limit)
--- @field include_diagnostics boolean Include buffer diagnostics
--- @field include_external_types boolean Include external package types
--- @field relevance_filter boolean Filter imports to used symbols only
--- @field current_range _99.Range? Range for filtering (e.g., current function)

--- @class _99.Lsp.ContextStats
--- @field symbols_included number
--- @field diagnostics_included number
--- @field imports_included number
--- @field imports_filtered number How many imports were filtered out
--- @field external_types_included number
--- @field budget_used number Characters consumed
--- @field budget_remaining number Characters remaining

--- Build complete LSP context for a RequestContext
--- Uses relevance-based filtering and budget tracking
--- @param request_context _99.RequestContext The request context
--- @param callback fun(result: string?, err: string?, stats: _99.Lsp.ContextStats?)
function M.build_context(request_context, callback)
    local lsp = require("99.lsp")
    local symbols_mod = require("99.lsp.symbols")
    local hover = require("99.lsp.hover")
    local imports_mod = require("99.lsp.imports")
    local formatter = require("99.lsp.formatter")
    local relevance = require("99.lsp.relevance")
    local diagnostics_mod = require("99.lsp.diagnostics")
    local external = require("99.lsp.external")
    local Budget = require("99.lsp.budget")

    local bufnr = request_context.buffer
    local config = lsp.config
    local logger = request_context.logger:clone():set_area("lsp.context")

    local stats = {
        symbols_included = 0,
        diagnostics_included = 0,
        imports_included = 0,
        imports_filtered = 0,
        external_types_included = 0,
        budget_used = 0,
        budget_remaining = 0,
    }

    if not lsp.is_available(bufnr) then
        logger:debug("LSP not available for buffer", "bufnr", bufnr)
        callback(nil, "lsp_not_available", stats)
        return
    end

    logger:debug("Building LSP context", "bufnr", bufnr)

    local budget = Budget.new(config.max_context_tokens, config.chars_per_token)
    imports_mod.reset_visited()

    local uri = lsp.buf_to_uri(bufnr)
    imports_mod.mark_visited(uri)

    local current_range = request_context.range
    symbols_mod.get_document_symbols(bufnr, function(doc_symbols, sym_err)
        if sym_err then
            logger:debug("Failed to get document symbols", "err", sym_err)
            callback(nil, sym_err, stats)
            return
        end

        if not doc_symbols or #doc_symbols == 0 then
            logger:debug("No symbols found")
            callback(nil, nil, stats)
            return
        end

        doc_symbols = symbols_mod.limit_symbols(doc_symbols, config.max_symbols)
        stats.symbols_included = #doc_symbols

        local used_symbols =
            relevance.find_used_symbols_smart(bufnr, current_range)

        hover.enrich_symbols(bufnr, doc_symbols, function(enriched_symbols)
            local diags = {}
            if config.include_diagnostics then
                diags = diagnostics_mod.get_errors_and_warnings(
                    bufnr,
                    current_range
                )
                stats.diagnostics_included = #diags
            end

            imports_mod.get_imports(bufnr, true, function(all_imports)
                local original_count = #(all_imports or {})

                local relevant_imports
                if config.relevance_filter and #used_symbols > 0 then
                    relevant_imports = relevance.filter_relevant_imports(
                        all_imports or {},
                        used_symbols
                    )
                else
                    relevant_imports = all_imports or {}
                end

                local valid_imports = {}
                for _, imp in ipairs(relevant_imports) do
                    if
                        not imp.is_external
                        and imp.resolved_uri
                        and not imports_mod.is_visited(imp.resolved_uri)
                    then
                        imports_mod.mark_visited(imp.resolved_uri)
                        table.insert(valid_imports, imp)
                    end
                end

                stats.imports_included = #valid_imports
                stats.imports_filtered = original_count - #valid_imports

                M._enrich_import_symbols(
                    bufnr,
                    valid_imports,
                    function(enriched_imports)
                        local ext_types = {}
                        if config.include_external_types then
                            external.get_external_types(
                                bufnr,
                                lsp.cache,
                                function(types)
                                    ext_types = types or {}
                                    stats.external_types_included = #ext_types
                                    M._format_and_return(
                                        request_context,
                                        enriched_symbols,
                                        enriched_imports,
                                        diags,
                                        ext_types,
                                        budget,
                                        stats,
                                        logger,
                                        callback
                                    )
                                end
                            )
                        else
                            M._format_and_return(
                                request_context,
                                enriched_symbols,
                                enriched_imports,
                                diags,
                                ext_types,
                                budget,
                                stats,
                                logger,
                                callback
                            )
                        end
                    end
                )
            end)
        end)
    end)
end

--- Format all context and return via callback
--- @private
function M._format_and_return(
    request_context,
    symbols,
    imports,
    diagnostics,
    external_types,
    budget,
    stats,
    logger,
    callback
)
    local formatter = require("99.lsp.formatter")
    local parts = {}

    local symbols_context =
        formatter.format_file_context(request_context.full_path, symbols)
    if budget:can_fit(symbols_context) then
        budget:consume("symbols", symbols_context)
        table.insert(parts, symbols_context)
    else
        local truncated, _ = budget:consume_partial("symbols", symbols_context)
        table.insert(parts, truncated)
    end

    if diagnostics and #diagnostics > 0 then
        local diag_context = formatter.format_diagnostics(diagnostics)
        if budget:can_fit(diag_context) then
            budget:consume("diagnostics", diag_context)
            table.insert(parts, diag_context)
        end
    end

    if imports and #imports > 0 then
        local import_context = formatter.format_imports(imports)
        if import_context ~= "" and budget:can_fit(import_context) then
            budget:consume("imports", import_context)
            table.insert(parts, import_context)
        end
    end

    if external_types and #external_types > 0 then
        local ext_context = formatter.format_external_types(external_types)
        if ext_context ~= "" and budget:can_fit(ext_context) then
            budget:consume("external_types", ext_context)
            table.insert(parts, ext_context)
        end
    end

    local budget_stats = budget:stats()
    stats.budget_used = budget_stats.used_chars
    stats.budget_remaining = budget_stats.remaining_chars

    local result = table.concat(parts, "\n")
    logger:debug(
        "Built LSP context",
        "length",
        #result,
        "budget_used",
        stats.budget_used
    )
    callback(result, nil, stats)
end

--- Enrich imported symbols with hover information
--- @param _source_bufnr number Source buffer (for LSP client) - reserved for future use
--- @param resolved_imports _99.Lsp.Import[] Resolved imports
--- @param callback fun(imports: _99.Lsp.Import[])
function M._enrich_import_symbols(_source_bufnr, resolved_imports, callback)
    if not resolved_imports or #resolved_imports == 0 then
        callback({})
        return
    end

    local hover = require("99.lsp.hover")
    local definitions = require("99.lsp.definitions")
    local pending = #resolved_imports
    local completed = false

    local function check_done()
        if completed then
            return
        end
        pending = pending - 1
        if pending == 0 then
            completed = true
            callback(resolved_imports)
        end
    end

    for _, imp in ipairs(resolved_imports) do
        if
            imp.resolved_symbols
            and #imp.resolved_symbols > 0
            and imp.resolved_uri
        then
            local file_path = vim.uri_to_fname(imp.resolved_uri)
            definitions.ensure_buffer_loaded(
                file_path,
                function(target_bufnr, err)
                    if err or not target_bufnr then
                        check_done()
                        return
                    end

                    hover.enrich_symbols(
                        target_bufnr,
                        imp.resolved_symbols,
                        function(enriched)
                            imp.resolved_symbols = enriched
                            check_done()
                        end
                    )
                end
            )
        else
            check_done()
        end
    end
end

--- Build context with timeout protection
--- @param request_context _99.RequestContext
--- @param timeout_ms number Timeout in milliseconds
--- @param callback fun(result: string?, err: string?, stats: _99.Lsp.ContextStats?)
function M.build_context_with_timeout(request_context, timeout_ms, callback)
    local completed = false
    local timer = vim.uv.new_timer()

    timer:start(
        timeout_ms,
        0,
        vim.schedule_wrap(function()
            if not completed then
                completed = true
                timer:stop()
                timer:close()
                callback(nil, "timeout", nil)
            end
        end)
    )

    M.build_context(request_context, function(result, err, stats)
        if completed then
            return
        end

        completed = true
        timer:stop()
        timer:close()
        callback(result, err, stats)
    end)
end

return M
