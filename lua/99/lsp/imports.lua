local M = {}

--- @class _99.Lsp.Import
--- @field module_path string The import path (e.g., "./database", "lodash")
--- @field symbols string[] Imported symbol names
--- @field position { line: number, character: number }? Position of import for definition lookup
--- @field resolved_uri string? URI of resolved target file
--- @field resolved_symbols _99.Lsp.Symbol[]? Resolved symbol information
--- @field is_external boolean? Whether this is an external package

--- Extract imports from document symbols
--- Looks for Module-kind symbols which often represent imports
--- @param symbols _99.Lsp.Symbol[] Document symbols
--- @return _99.Lsp.Import[] Extracted imports
function M.extract_imports_from_symbols(symbols)
    local formatter = require("99.lsp.formatter")
    local imports = {}

    for _, symbol in ipairs(symbols) do
        if symbol.kind == formatter.SymbolKind.Module then
            table.insert(imports, {
                module_path = symbol.name,
                symbols = {},
                position = symbol.range and symbol.range.start,
                resolved_uri = nil,
                resolved_symbols = nil,
                is_external = nil,
            })
        end
    end

    return imports
end

--- Extract imports by parsing buffer content for common import patterns
--- @param bufnr number Buffer number
--- @return _99.Lsp.Import[] Extracted imports
function M.extract_imports_from_buffer(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local imports = {}
    local filetype = vim.bo[bufnr].filetype

    for line_num, line in ipairs(lines) do
        local import

        if filetype == "lua" then
            local module = line:match('require%s*%(?%s*["\']([^"\']+)["\']')
            if module then
                local var_name = line:match("^%s*local%s+([%w_]+)%s*=") or module:match("([^%.]+)$")
                if var_name then
                    import = {
                        module_path = module,
                        symbols = { var_name },
                        position = { line = line_num - 1, character = line:find("require") - 1 or 0 },
                    }
                end
            end
        elseif filetype == "typescript" or filetype == "typescriptreact" or filetype == "javascript" or filetype == "javascriptreact" then
            local named, module = line:match('import%s*{([^}]+)}%s*from%s*["\']([^"\']+)["\']')
            if named and module then
                local symbol_names = {}
                for name in named:gmatch("([%w_]+)") do
                    table.insert(symbol_names, name)
                end
                import = {
                    module_path = module,
                    symbols = symbol_names,
                    position = { line = line_num - 1, character = 0 },
                }
            else
                local default_import, mod = line:match('import%s+([%w_]+)%s+from%s*["\']([^"\']+)["\']')
                if default_import and mod then
                    import = {
                        module_path = mod,
                        symbols = { default_import },
                        position = { line = line_num - 1, character = 0 },
                    }
                else
                    local namespace, mod2 = line:match('import%s*%*%s*as%s+([%w_]+)%s+from%s*["\']([^"\']+)["\']')
                    if namespace and mod2 then
                        import = {
                            module_path = mod2,
                            symbols = { namespace },
                            position = { line = line_num - 1, character = 0 },
                        }
                    end
                end
            end
        elseif filetype == "python" then
            local module, named = line:match("^%s*from%s+([%w_.]+)%s+import%s+(.+)$")
            if module and named then
                local symbol_names = {}
                for name in named:gmatch("([%w_]+)") do
                    if name ~= "as" then
                        table.insert(symbol_names, name)
                    end
                end
                import = {
                    module_path = module,
                    symbols = symbol_names,
                    position = { line = line_num - 1, character = 0 },
                }
            else
                local mod = line:match("^%s*import%s+([%w_.]+)")
                if mod then
                    import = {
                        module_path = mod,
                        symbols = { mod:match("([^%.]+)$") },
                        position = { line = line_num - 1, character = 0 },
                    }
                end
            end
        elseif filetype == "go" then
            local pkg = line:match('import%s*["\']([^"\']+)["\']')
                or line:match('^%s*["\']([^"\']+)["\']')
            if pkg then
                import = {
                    module_path = pkg,
                    symbols = { pkg:match("([^/]+)$") },
                    position = { line = line_num - 1, character = 0 },
                }
            end
        end

        if import then
            table.insert(imports, import)
        end
    end

    return imports
end

--- Resolve an import to its target file and symbols
--- @param bufnr number Source buffer number
--- @param import _99.Lsp.Import Import to resolve
--- @param callback fun(resolved: _99.Lsp.Import) Callback with resolved import
function M.resolve_import(bufnr, import, callback)
    local definitions = require("99.lsp.definitions")
    local symbols = require("99.lsp.symbols")

    if not import.position then
        callback(import)
        return
    end

    definitions.get_definition_with_buffer(bufnr, import.position, function(def, target_bufnr, err)
        if err or not def or not target_bufnr then
            callback(import)
            return
        end

        import.resolved_uri = def.uri
        import.is_external = definitions.is_external_definition(def)

        if import.is_external then
            callback(import)
            return
        end

        symbols.get_document_symbols(target_bufnr, function(target_symbols, sym_err)
            if sym_err or not target_symbols then
                callback(import)
                return
            end

            if import.symbols and #import.symbols > 0 then
                local imported_names = {}
                for _, name in ipairs(import.symbols) do
                    imported_names[name] = true
                end

                local filtered = {}
                for _, sym in ipairs(target_symbols) do
                    if imported_names[sym.name] then
                        table.insert(filtered, sym)
                    end
                end
                import.resolved_symbols = filtered
            else
                import.resolved_symbols = target_symbols
            end

            callback(import)
        end)
    end)
end

--- Resolve multiple imports
--- @param bufnr number Source buffer number
--- @param imports _99.Lsp.Import[] Imports to resolve
--- @param callback fun(resolved: _99.Lsp.Import[]) Callback with resolved imports
function M.resolve_imports(bufnr, imports, callback)
    if not imports or #imports == 0 then
        callback({})
        return
    end

    local resolved = {}
    local pending = #imports

    for i, import in ipairs(imports) do
        M.resolve_import(bufnr, import, function(result)
            resolved[i] = result
            pending = pending - 1
            if pending == 0 then
                callback(resolved)
            end
        end)
    end
end

--- Get imports from a buffer and optionally resolve them
--- @param bufnr number Buffer number
--- @param resolve boolean Whether to resolve imports to target files
--- @param callback fun(imports: _99.Lsp.Import[]) Callback with imports
function M.get_imports(bufnr, resolve, callback)
    -- First try to get imports from buffer parsing (more reliable)
    local imports = M.extract_imports_from_buffer(bufnr)

    if not resolve then
        callback(imports)
        return
    end

    M.resolve_imports(bufnr, imports, callback)
end

--- Track visited URIs to prevent circular imports
--- @type table<string, boolean>
local visited_uris = {}

--- Reset visited URIs tracking (call before starting a new context build)
function M.reset_visited()
    visited_uris = {}
end

--- Check if a URI has been visited
--- @param uri string
--- @return boolean
function M.is_visited(uri)
    return visited_uris[uri] == true
end

--- Mark a URI as visited
--- @param uri string
function M.mark_visited(uri)
    visited_uris[uri] = true
end

return M
