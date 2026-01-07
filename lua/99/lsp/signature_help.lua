local M = {}

--- @class _99.Lsp.ParameterInformation
--- @field label string|number[] Label string or [startOffset, endOffset] tuple
--- @field documentation string? Parameter documentation

--- @class _99.Lsp.SignatureInformation
--- @field label string The label of this signature (e.g., "fn(a: number, b: string): void")
--- @field documentation string? Documentation for this signature
--- @field parameters _99.Lsp.ParameterInformation[]? Parameters of this signature
--- @field activeParameter number? Override for active parameter (0-indexed)

--- @class _99.Lsp.SignatureHelp
--- @field signatures _99.Lsp.SignatureInformation[] Available signatures
--- @field activeSignature number? Index of active signature (0-indexed)
--- @field activeParameter number? Index of active parameter (0-indexed)

--- Parse LSP SignatureHelp response into our internal format
--- @param result table LSP SignatureHelp response
--- @return _99.Lsp.SignatureHelp?
local function parse_signature_help(result)
    if not result or not result.signatures or #result.signatures == 0 then
        return nil
    end

    local signatures = {}
    for _, sig in ipairs(result.signatures) do
        local params = nil
        if sig.parameters and #sig.parameters > 0 then
            params = {}
            for _, param in ipairs(sig.parameters) do
                table.insert(params, {
                    label = param.label,
                    documentation = type(param.documentation) == "table"
                            and param.documentation.value
                        or param.documentation,
                })
            end
        end

        table.insert(signatures, {
            label = sig.label,
            documentation = type(sig.documentation) == "table"
                    and sig.documentation.value
                or sig.documentation,
            parameters = params,
            activeParameter = sig.activeParameter,
        })
    end

    return {
        signatures = signatures,
        activeSignature = result.activeSignature,
        activeParameter = result.activeParameter,
    }
end

--- Get signature help at a position
--- @param bufnr number Buffer number
--- @param position { line: number, character: number } LSP position (0-based)
--- @param callback fun(result: _99.Lsp.SignatureHelp?, err: string?)
function M.get_signature_help(bufnr, position, callback)
    local lsp = require("99.lsp")

    if not lsp.is_available(bufnr) then
        callback(nil, "no_lsp_client")
        return
    end

    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = position,
    }

    vim.lsp.buf_request(
        bufnr,
        "textDocument/signatureHelp",
        params,
        function(err, result, _, _)
            if err then
                callback(nil, vim.inspect(err))
                return
            end

            local parsed = parse_signature_help(result)
            callback(parsed, nil)
        end
    )
end

--- Format a signature for display
--- @param sig _99.Lsp.SignatureInformation
--- @return string Formatted signature
function M.format_signature(sig)
    return sig.label
end

--- Format the active parameter with highlighting info
--- @param sig_help _99.Lsp.SignatureHelp
--- @return string? The active parameter label, or nil
function M.format_active_parameter(sig_help)
    if not sig_help or not sig_help.signatures or #sig_help.signatures == 0 then
        return nil
    end

    local active_sig_idx = (sig_help.activeSignature or 0) + 1
    local sig = sig_help.signatures[active_sig_idx]
    if not sig or not sig.parameters then
        return nil
    end

    local active_param_idx = sig.activeParameter
        or sig_help.activeParameter
        or 0
    local param = sig.parameters[active_param_idx + 1]
    if not param then
        return nil
    end

    if type(param.label) == "string" then
        return param.label
    elseif type(param.label) == "table" then
        local start_offset = param.label[1] + 1
        local end_offset = param.label[2]
        return string.sub(sig.label, start_offset, end_offset)
    end

    return nil
end

--- Get all parameter names from signature help
--- @param sig_help _99.Lsp.SignatureHelp
--- @return string[] Parameter names/labels
function M.get_parameter_names(sig_help)
    if not sig_help or not sig_help.signatures or #sig_help.signatures == 0 then
        return {}
    end

    local active_sig_idx = (sig_help.activeSignature or 0) + 1
    local sig = sig_help.signatures[active_sig_idx]
    if not sig or not sig.parameters then
        return {}
    end

    local names = {}
    for _, param in ipairs(sig.parameters) do
        if type(param.label) == "string" then
            table.insert(names, param.label)
        elseif type(param.label) == "table" then
            local start_offset = param.label[1] + 1
            local end_offset = param.label[2]
            table.insert(names, string.sub(sig.label, start_offset, end_offset))
        end
    end
    return names
end

--- Batch request signature help for multiple positions
--- @param bufnr number Buffer number
--- @param positions { line: number, character: number }[] LSP positions (0-based)
--- @param callback fun(results: (_99.Lsp.SignatureHelp?)[])
--- @return _99.Lsp.ParallelController? controller Control object for cancellation
function M.batch_signature_help(bufnr, positions, callback)
    local parallel = require("99.lsp.parallel")

    return parallel.parallel_map(positions, function(position, _, done)
        M.get_signature_help(bufnr, position, function(result, err)
            done(result, err)
        end)
    end, callback)
end

--- Batch request signature help with timeout
--- @param bufnr number Buffer number
--- @param positions { line: number, character: number }[] LSP positions (0-based)
--- @param timeout_ms number Timeout in milliseconds
--- @param callback fun(results: (_99.Lsp.SignatureHelp?)[], timed_out: boolean)
--- @return _99.Lsp.ParallelController? controller
function M.batch_signature_help_with_timeout(
    bufnr,
    positions,
    timeout_ms,
    callback
)
    local parallel = require("99.lsp.parallel")

    return parallel.parallel_map_with_timeout(
        positions,
        function(position, _, done)
            M.get_signature_help(bufnr, position, function(result, err)
                done(result, err)
            end)
        end,
        timeout_ms,
        callback
    )
end

--- Format signature help for context output
--- @param sig_help _99.Lsp.SignatureHelp
--- @return string Formatted output
function M.format_for_context(sig_help)
    if not sig_help or not sig_help.signatures or #sig_help.signatures == 0 then
        return ""
    end

    local parts = {}
    for _, sig in ipairs(sig_help.signatures) do
        table.insert(parts, sig.label)
        if sig.documentation and sig.documentation ~= "" then
            table.insert(parts, "  " .. sig.documentation)
        end
    end

    return table.concat(parts, "\n")
end

return M
