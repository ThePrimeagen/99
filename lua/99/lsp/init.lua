--- @class _99.Lsp.Config
--- @field enabled boolean Enable/disable LSP context gathering
--- @field import_depth number Depth of import traversal (0 = current file only, 1 = direct imports)
--- @field format "compact"|"verbose" Output format style
--- @field timeout number LSP request timeout in milliseconds
--- @field max_symbols number Maximum symbols per file
--- @field include_private boolean Include private/internal symbols
--- @field max_context_tokens number Maximum tokens for context budget (default 8000)
--- @field chars_per_token number Characters per token estimate (default 4)
--- @field include_diagnostics boolean Include buffer diagnostics in context (default true)
--- @field include_external_types boolean Include external package type signatures (default true)
--- @field external_type_ttl number TTL for external type cache in ms (default 3600000 = 1hr)
--- @field relevance_filter boolean Only include imports with symbols used in current range (default true)

--- @class _99.Lsp
--- @field config _99.Lsp.Config
--- @field cache _99.Lsp.Cache?
local M = {}

--- Default configuration for LSP context gathering
--- @return _99.Lsp.Config
function M.default_config()
    return {
        enabled = true,
        import_depth = 1,
        format = "compact",
        timeout = 5000,
        max_symbols = 100,
        include_private = false,
        max_context_tokens = 8000,
        chars_per_token = 4,
        include_diagnostics = true,
        include_external_types = true,
        external_type_ttl = 3600000,
        relevance_filter = true,
    }
end

--- Module-level configuration
--- @type _99.Lsp.Config
M.config = M.default_config()

--- Module-level cache (initialized in setup)
--- @type _99.Lsp.Cache?
M.cache = nil

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

--- Get the first LSP client with documentSymbol capability for a buffer
--- @param bufnr number Buffer number
--- @return vim.lsp.Client? The client, or nil if none available
function M.get_client(bufnr)
    local clients = vim.lsp.get_clients({ bufnr = bufnr })

    for _, client in ipairs(clients) do
        if
            client.server_capabilities
            and client.server_capabilities.documentSymbolProvider
        then
            return client
        end
    end

    return nil
end

--- Get the URI for a buffer
--- @param bufnr number Buffer number
--- @return string URI string
function M.buf_to_uri(bufnr)
    return vim.uri_from_bufnr(bufnr)
end

--- Get buffer number from URI
--- @param uri string URI string
--- @return number? Buffer number or nil
function M.uri_to_bufnr(uri)
    local path = vim.uri_to_fname(uri)
    local bufnr = vim.fn.bufnr(path)
    if bufnr == -1 then
        return nil
    end
    return bufnr
end

--- Main entry point for getting LSP context with fallback to treesitter
--- @param request_context _99.RequestContext
--- @param callback fun(result: string?, err: string?, stats: _99.Lsp.ContextStats?)
function M.get_context(request_context, callback)
    local bufnr = request_context.buffer
    if M.is_available(bufnr) then
        local ctx_builder = require("99.lsp.context")
        ctx_builder.build_context_with_timeout(
            request_context,
            M.config.timeout,
            function(result, _err, stats)
                if result then
                    callback(result, nil, stats)
                else
                    local fallback = require("99.lsp.fallback")
                    fallback.get_treesitter_context(request_context, callback)
                end
            end
        )
    else
        local fallback = require("99.lsp.fallback")
        fallback.get_treesitter_context(request_context, callback)
    end
end

return M
