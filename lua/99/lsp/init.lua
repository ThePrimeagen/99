--- @class _99.Lsp.Config
--- @field enabled boolean Enable/disable LSP context gathering
--- @field import_depth number Depth of import traversal (0 = current file only, 1 = direct imports)
--- @field format "compact"|"verbose" Output format style
--- @field timeout number LSP request timeout in milliseconds
--- @field max_symbols number Maximum symbols per file
--- @field include_private boolean Include private/internal symbols

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

    -- Check if any client supports documentSymbol
    for _, client in ipairs(clients) do
        if client.server_capabilities and client.server_capabilities.documentSymbolProvider then
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
        if client.server_capabilities and client.server_capabilities.documentSymbolProvider then
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

return M
