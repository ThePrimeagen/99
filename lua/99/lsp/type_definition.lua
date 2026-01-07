local M = {}

--- @class _99.Lsp.TypeDefinition
--- @field uri string Document URI
--- @field range { start: { line: number, character: number }, ["end"]: { line: number, character: number } }
--- @field file_path string Converted from URI (convenience)
--- @field target_selection_range { start: { line: number, character: number }, ["end"]: { line: number, character: number } }? For LocationLink

--- Parse LSP typeDefinition response (handles Location, Location[], LocationLink[])
--- @param result table|table[]|nil LSP response
--- @return _99.Lsp.TypeDefinition[]
function M.parse_type_definition_response(result)
    if not result then
        return {}
    end

    local definitions = {}

    local items = result
    if result.uri then
        items = { result }
    end

    for _, item in ipairs(items) do
        local def = {}

        if item.targetUri then
            def.uri = item.targetUri
            def.range = item.targetRange
            def.target_selection_range = item.targetSelectionRange
        else
            def.uri = item.uri
            def.range = item.range
        end

        def.file_path = vim.uri_to_fname(def.uri)
        table.insert(definitions, def)
    end

    return definitions
end

--- Get type definition at a position
--- @param bufnr number Buffer number
--- @param position { line: number, character: number } LSP position (0-based)
--- @param callback fun(results: _99.Lsp.TypeDefinition[], err: string?)
function M.get_type_definition(bufnr, position, callback)
    local lsp = require("99.lsp")

    if not lsp.is_available(bufnr) then
        callback({}, "no_lsp_client")
        return
    end

    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
        position = position,
    }

    vim.lsp.buf_request(
        bufnr,
        "textDocument/typeDefinition",
        params,
        function(err, result, _, _)
            if err then
                callback({}, vim.inspect(err))
                return
            end

            local definitions = M.parse_type_definition_response(result)
            callback(definitions, nil)
        end
    )
end

--- Get type definition and ensure target buffer is loaded
--- @param bufnr number Buffer number
--- @param position { line: number, character: number } LSP position (0-based)
--- @param callback fun(results: { def: _99.Lsp.TypeDefinition, bufnr: number }[], err: string?)
function M.get_type_with_buffer(bufnr, position, callback)
    local definitions_mod = require("99.lsp.definitions")

    M.get_type_definition(bufnr, position, function(definitions, err)
        if err or #definitions == 0 then
            callback({}, err)
            return
        end

        local results = {}
        local pending = #definitions
        local completed = false

        local function check_done()
            if completed then
                return
            end
            pending = pending - 1
            if pending == 0 then
                completed = true
                callback(results, nil)
            end
        end

        for _, def in ipairs(definitions) do
            definitions_mod.ensure_buffer_loaded(
                def.file_path,
                function(target_bufnr, load_err)
                    if not load_err and target_bufnr then
                        table.insert(results, {
                            def = def,
                            bufnr = target_bufnr,
                        })
                    end
                    check_done()
                end
            )
        end
    end)
end

--- Batch request type definitions for multiple positions
--- @param bufnr number Buffer number
--- @param positions { line: number, character: number }[] LSP positions (0-based)
--- @param callback fun(results: _99.Lsp.TypeDefinition[][])
function M.batch_type_definitions(bufnr, positions, callback)
    if not positions or #positions == 0 then
        callback({})
        return
    end

    local results = {}
    local pending = #positions
    local completed = false

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

    for i, position in ipairs(positions) do
        M.get_type_definition(bufnr, position, function(defs, _)
            results[i] = defs
            check_done()
        end)
    end
end

--- Check if type definition points to an external package
--- @param def _99.Lsp.TypeDefinition
--- @return boolean
function M.is_external(def)
    local definitions_mod = require("99.lsp.definitions")
    return definitions_mod.is_external_definition(def.uri)
end

--- Format type definition for context output
--- @param def _99.Lsp.TypeDefinition
--- @return string
function M.format_for_context(def)
    local parts = {}
    table.insert(parts, def.file_path)
    if def.range then
        table.insert(
            parts,
            string.format(":%d:%d", def.range.start.line + 1, def.range.start.character + 1)
        )
    end
    return table.concat(parts, "")
end

return M
