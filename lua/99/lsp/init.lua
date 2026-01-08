--- @class _99.Lsp.Config
--- @field enabled boolean Enable/disable LSP context gathering
--- @field format "compact"|"verbose" Output format style
--- @field timeout number LSP request timeout in milliseconds
--- @field max_symbols number Maximum symbols per file
--- @field include_private boolean Include private/internal symbols
--- @field max_context_tokens number Maximum tokens for context budget (default 8000)
--- @field chars_per_token number Characters per token estimate (default 4)
--- @field include_diagnostics boolean Include buffer diagnostics in context (default true)
--- @field include_inlay_hints boolean Include LSP 3.17 inlay hints (default false)

--- @class _99.Lsp
--- @field config _99.Lsp.Config
local M = {}

--- Default configuration for LSP context gathering
--- @return _99.Lsp.Config
function M.default_config()
    return {
        enabled = true,
        format = "compact",
        timeout = 5000,
        max_symbols = 100,
        include_private = false,
        max_context_tokens = 8000,
        chars_per_token = 4,
        include_diagnostics = true,
        include_inlay_hints = false,
    }
end

--- Module-level configuration
--- @type _99.Lsp.Config
M.config = M.default_config()

--- Setup the LSP module with the given configuration
--- @param config _99.Lsp.Config?
function M.setup(config)
    if config then
        M.config = vim.tbl_deep_extend("force", M.default_config(), config)
    end
end

--- Check if an LSP client with documentSymbol capability is available for a buffer
--- @param bufnr number Buffer number to check
--- @return boolean True if LSP with documentSymbol is available
function M.is_available(bufnr)
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if #clients == 0 then
        return false
    end

    for _, client in ipairs(clients) do
        if
            client.server_capabilities
            and client.server_capabilities.documentSymbolProvider
        then
            return true
        end
    end

    return false
end

--- Main entry point for getting LSP context
--- Uses coroutine-based context builder with TreeSitter fallback
--- @param request_context _99.RequestContext
--- @param callback fun(result: string?, err: string?, stats: _99.Lsp.ContextStats?)
function M.get_context(request_context, callback)
    local ctx_builder = require("99.lsp.context")
    ctx_builder.build_context_with_timeout(
        request_context,
        M.config.timeout,
        callback
    )
end

return M
