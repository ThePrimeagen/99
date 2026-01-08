local M = {}

--- @class _99.Lsp.ContextOptions
--- @field budget _99.Lsp.Budget? Token budget (nil = no limit)
--- @field include_diagnostics boolean Include buffer diagnostics
--- @field include_inlay_hints boolean Include LSP 3.17 inlay hints
--- @field current_range _99.Range? Range for filtering (e.g., current function)

--- @class _99.Lsp.ContextStats
--- @field symbols_included number
--- @field diagnostics_included number
--- @field inlay_hints_included number
--- @field budget_used number Characters consumed
--- @field budget_remaining number Characters remaining
--- @field capabilities_used string[] Which LSP capabilities were used

--- Get errors and warnings for context
--- @param bufnr number Buffer number
--- @param range _99.Range? Optional range filter
--- @return _99.Lsp.Diagnostic[]
function M._get_diagnostics(bufnr, range)
    local diags = vim.diagnostic.get(bufnr)

    local filtered = {}
    for _, diag in ipairs(diags) do
        if diag.severity <= vim.diagnostic.severity.WARN then
            if range then
                local geo = require("99.geo")
                local diag_point =
                    geo.Point:from_lsp_position(diag.lnum, diag.col)
                if range:contains(diag_point) then
                    table.insert(filtered, diag)
                end
            else
                table.insert(filtered, diag)
            end
        end
    end

    return filtered
end

--- Build context asynchronously using coroutines
--- @param request_context _99.RequestContext
--- @return string? result
--- @return string? err
--- @return _99.Lsp.ContextStats? stats
local function build_context_async(request_context)
    local async = require("99.lsp.async")
    local requests = require("99.lsp.requests")
    local formatter = require("99.lsp.formatter")
    local Budget = require("99.lsp.budget")
    local lsp = require("99.lsp")

    local bufnr = request_context.buffer
    local config = lsp.config
    local logger = request_context.logger:clone():set_area("lsp.context")
    local current_range = request_context.range

    local stats = {
        symbols_included = 0,
        diagnostics_included = 0,
        inlay_hints_included = 0,
        budget_used = 0,
        budget_remaining = 0,
        capabilities_used = {},
    }

    local budget = Budget.new(config.max_context_tokens, config.chars_per_token)

    -- Require LSP to be available
    if not lsp.is_available(bufnr) then
        logger:debug("LSP not available", "bufnr", bufnr)
        return nil, nil, stats
    end

    logger:debug("Building LSP context", "bufnr", bufnr)

    local caps = requests.get_server_capabilities(bufnr)

    local raw_symbols, sym_err = async.await(function(cb)
        requests.document_symbols(bufnr, cb)
    end)

    if sym_err then
        logger:debug("Failed to get document symbols", "err", sym_err)
        return nil, sym_err, stats
    end

    if not raw_symbols or #raw_symbols == 0 then
        logger:debug("No LSP symbols available")
        return nil, nil, stats
    end

    table.insert(stats.capabilities_used, "textDocument/documentSymbol")

    local doc_symbols = requests.parse_symbol_response(raw_symbols)
    doc_symbols = requests.limit_symbols(doc_symbols, config.max_symbols)
    stats.symbols_included = #doc_symbols

    local positions = {}
    for _, sym in ipairs(doc_symbols) do
        if sym.range and sym.range.start then
            table.insert(positions, {
                line = sym.range.start.line,
                character = sym.range.start.character,
            })
        end
    end

    if #positions > 0 and caps.hoverProvider then
        local hover_results = async.await(function(cb)
            requests.batch_hover(bufnr, positions, cb)
        end)

        if hover_results then
            table.insert(stats.capabilities_used, "textDocument/hover")
            for i, result in pairs(hover_results) do
                if result and doc_symbols[i] then
                    local sig = requests.parse_hover_contents(result.contents)
                    if sig and sig ~= "" then
                        doc_symbols[i].signature = sig
                    end
                end
            end
        end
    end

    local inlay_hints = {}
    if config.include_inlay_hints and caps.inlayHintProvider then
        local hint_range = {
            start = { line = 0, character = 0 },
            ["end"] = {
                line = vim.api.nvim_buf_line_count(bufnr),
                character = 0,
            },
        }
        if current_range then
            local sr, _ = current_range.start:to_vim()
            local er, _ = current_range.end_:to_vim()
            hint_range = {
                start = { line = sr, character = 0 },
                ["end"] = { line = er + 1, character = 0 },
            }
        end

        local hints_result = async.await(function(cb)
            requests.inlay_hints(bufnr, hint_range, cb)
        end)

        if hints_result then
            table.insert(stats.capabilities_used, "textDocument/inlayHint")
            inlay_hints = hints_result
            stats.inlay_hints_included = #inlay_hints
        end
    end

    local diagnostics = {}
    if config.include_diagnostics then
        diagnostics = M._get_diagnostics(bufnr, current_range)
        stats.diagnostics_included = #diagnostics
    end

    local parts = {}

    local symbols_context =
        formatter.format_file_context(request_context.full_path, doc_symbols)
    if budget:can_fit(symbols_context) then
        budget:consume("symbols", symbols_context)
        table.insert(parts, symbols_context)
    else
        local truncated, _ = budget:consume_partial("symbols", symbols_context)
        table.insert(parts, truncated)
    end

    if #diagnostics > 0 then
        local diag_context = formatter.format_diagnostics(diagnostics)
        if diag_context ~= "" and budget:can_fit(diag_context) then
            budget:consume("diagnostics", diag_context)
            table.insert(parts, diag_context)
        end
    end

    if #inlay_hints > 0 then
        local hints_context = formatter.format_inlay_hints(inlay_hints)
        if hints_context ~= "" and budget:can_fit(hints_context) then
            budget:consume("inlay_hints", hints_context)
            table.insert(parts, hints_context)
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

    return result, nil, stats
end

--- Build complete LSP context for a RequestContext
--- Uses coroutine-based async operations and budget tracking
--- @param request_context _99.RequestContext The request context
--- @param callback fun(result: string?, err: string?, stats: _99.Lsp.ContextStats?)
function M.build_context(request_context, callback)
    local async = require("99.lsp.async")

    async.run(function()
        return build_context_async(request_context)
    end, function(result, err)
        if err then
            local err_msg = type(err) == "table" and err.message
                or tostring(err)
            callback(nil, err_msg, nil)
        elseif type(result) == "table" then
            callback(result[1], result[2], result[3])
        else
            callback(result, nil, nil)
        end
    end)
end

--- Build context with timeout protection
--- @param request_context _99.RequestContext
--- @param timeout_ms number Timeout in milliseconds
--- @param callback fun(result: string?, err: string?, stats: _99.Lsp.ContextStats?)
function M.build_context_with_timeout(request_context, timeout_ms, callback)
    local async = require("99.lsp.async")

    async.run_with_timeout(
        function()
            return build_context_async(request_context)
        end,
        timeout_ms,
        function(result, err)
            if err then
                callback(nil, err, nil)
            elseif type(result) == "table" then
                callback(result[1], result[2], result[3])
            else
                callback(result, nil, nil)
            end
        end
    )
end

return M
