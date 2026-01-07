local M = {}

--- @class _99.Lsp.Definition
--- @field uri string File URI where definition is located
--- @field range { start: { line: number, character: number }, ["end"]: { line: number, character: number } }
--- @field file_path string Resolved local file path
--- @field targetSelectionRange { start: { line: number, character: number }, ["end"]: { line: number, character: number } }?

--- Parse a Location response
--- @param location table LSP Location
--- @return _99.Lsp.Definition
local function parse_location(location)
    return {
        uri = location.uri,
        range = location.range,
        file_path = vim.uri_to_fname(location.uri),
        targetSelectionRange = nil,
    }
end

--- Parse a LocationLink response (LSP 3.14+)
--- @param link table LSP LocationLink
--- @return _99.Lsp.Definition
local function parse_location_link(link)
    return {
        uri = link.targetUri,
        range = link.targetRange,
        file_path = vim.uri_to_fname(link.targetUri),
        targetSelectionRange = link.targetSelectionRange,
    }
end

--- Check if response is LocationLink format
--- @param item table Single response item
--- @return boolean
local function is_location_link(item)
    return item.targetUri ~= nil
end

--- Parse definition response (handles Location, Location[], LocationLink[])
--- @param result any LSP definition response
--- @return _99.Lsp.Definition[]
function M.parse_definition_response(result)
    if not result then
        return {}
    end

    local definitions = {}

    if result.uri then
        table.insert(definitions, parse_location(result))
        return definitions
    end

    if type(result) == "table" and #result > 0 then
        for _, item in ipairs(result) do
            if is_location_link(item) then
                table.insert(definitions, parse_location_link(item))
            else
                table.insert(definitions, parse_location(item))
            end
        end
    end

    return definitions
end

--- Make a textDocument/definition request for a specific position
--- @param bufnr number Buffer number
--- @param position { line: number, character: number } LSP position (0-based)
--- @param callback fun(definitions: _99.Lsp.Definition[]?, err: string?) Callback
function M.get_definition(bufnr, position, callback)
    local lsp = require("99.lsp")

    local client = lsp.get_client(bufnr)
    if not client then
        callback(nil, "no_lsp_client")
        return
    end

    if not client.server_capabilities or not client.server_capabilities.definitionProvider then
        callback(nil, "definition_not_supported")
        return
    end

    local params = {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = position,
    }

    vim.lsp.buf_request(bufnr, "textDocument/definition", params, function(err, result, _, _)
        if err then
            callback(nil, vim.inspect(err))
            return
        end

        local definitions = M.parse_definition_response(result)
        callback(definitions, nil)
    end)
end

--- Load a file into a buffer without switching to it
--- @param file_path string File path to load
--- @param callback fun(bufnr: number?, err: string?) Callback with buffer number
function M.ensure_buffer_loaded(file_path, callback)
    if vim.fn.filereadable(file_path) ~= 1 then
        callback(nil, "file_not_readable: " .. file_path)
        return
    end

    local bufnr = vim.fn.bufnr(file_path)
    if bufnr == -1 then
        bufnr = vim.fn.bufadd(file_path)
    end

    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
    end

    vim.schedule(function()
        callback(bufnr, nil)
    end)
end

--- Get definition and load the target file
--- @param bufnr number Source buffer number
--- @param position { line: number, character: number } Position to get definition for
--- @param callback fun(definition: _99.Lsp.Definition?, target_bufnr: number?, err: string?)
function M.get_definition_with_buffer(bufnr, position, callback)
    M.get_definition(bufnr, position, function(definitions, err)
        if err then
            callback(nil, nil, err)
            return
        end

        if not definitions or #definitions == 0 then
            callback(nil, nil, nil)
            return
        end

        local def = definitions[1]
        M.ensure_buffer_loaded(def.file_path, function(target_bufnr, load_err)
            if load_err then
                callback(def, nil, load_err)
                return
            end

            callback(def, target_bufnr, nil)
        end)
    end)
end

--- Check if a definition points to an external package (not in workspace)
--- @param definition _99.Lsp.Definition
--- @return boolean
function M.is_external_definition(definition)
    local cwd = vim.fn.getcwd()
    local file_path = definition.file_path

    if file_path:sub(1, #cwd) == cwd then
        return false
    end

    local external_patterns = {
        "/node_modules/",
        "/.npm/",
        "/site-packages/",
        "/.local/lib/",
        "/usr/lib/",
        "/usr/local/lib/",
        "/.cargo/",
        "/go/pkg/",
    }

    for _, pattern in ipairs(external_patterns) do
        if file_path:find(pattern, 1, true) then
            return true
        end
    end

    return false
end

return M
