local M = {}

--- @class _99.Lsp.ExternalType
--- @field symbol_name string Name of the symbol
--- @field type_signature string Type signature (compact, no implementation)
--- @field package_name string Package/module name
--- @field uri string Source URI
--- @field position { line: number, character: number }? Position in file

--- Known external package path patterns
--- @type string[]
M.external_patterns = {
    "/node_modules/",
    "/.npm/",
    "/site-packages/",
    "/.local/lib/",
    "/usr/lib/",
    "/usr/local/lib/",
    "/.cargo/",
    "/go/pkg/",
    "/.rustup/",
    "/.pyenv/",
    "/.nvm/",
    "/vendor/",
    "/.luarocks/",
}

--- Check if a URI points to an external package
--- @param uri string File URI
--- @return boolean
function M.is_external_uri(uri)
    local file_path = vim.uri_to_fname(uri)
    local cwd = vim.fn.getcwd()

    if file_path:sub(1, #cwd) == cwd then
        return false
    end

    for _, pattern in ipairs(M.external_patterns) do
        if file_path:find(pattern, 1, true) then
            return true
        end
    end

    return false
end

--- Extract package name from a file path
--- @param file_path string File path
--- @return string Package name
function M.extract_package_name(file_path)
    local npm_pkg = file_path:match("/node_modules/(@[^/]+/[^/]+)")
        or file_path:match("/node_modules/([^/]+)")
    if npm_pkg then
        return npm_pkg
    end

    local py_pkg = file_path:match("/site%-packages/([^/]+)")
    if py_pkg then
        return py_pkg
    end

    local go_pkg = file_path:match("/go/pkg/mod/([^@]+)")
    if go_pkg then
        return go_pkg
    end

    local rust_pkg = file_path:match("/.cargo/registry/src/[^/]+/([^%-]+)")
    if rust_pkg then
        return rust_pkg
    end

    local lua_pkg = file_path:match("/.luarocks/share/lua/[^/]+/([^/]+)")
    if lua_pkg then
        return lua_pkg
    end

    return file_path:match("([^/]+)/[^/]+$") or "unknown"
end

--- Identify external imports from a buffer
--- @param bufnr number Buffer number
--- @param callback fun(imports: _99.Lsp.Import[])
function M.identify_external_imports(bufnr, callback)
    local imports_mod = require("99.lsp.imports")

    imports_mod.get_imports(bufnr, true, function(imports)
        local external = {}
        for _, imp in ipairs(imports or {}) do
            if imp.is_external and imp.resolved_uri then
                table.insert(external, imp)
            end
        end
        callback(external)
    end)
end

--- Find which symbols from external imports are actually used in the buffer
--- @param bufnr number Buffer number
--- @param external_imports _99.Lsp.Import[] External imports
--- @return string[] Used symbol names
function M.get_used_symbols(bufnr, external_imports)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    local used = {}
    local seen = {}

    for _, imp in ipairs(external_imports) do
        for _, symbol_name in ipairs(imp.symbols or {}) do
            if not seen[symbol_name] then
                local pattern = "[^%w_]" .. vim.pesc(symbol_name) .. "[^%w_]"
                if content:find(pattern) or content:find("^" .. vim.pesc(symbol_name) .. "[^%w_]") then
                    table.insert(used, symbol_name)
                    seen[symbol_name] = true
                end
            end
        end
    end

    return used
end

--- Fetch type signatures for external symbols using hover
--- @param bufnr number Buffer number (source buffer for LSP client)
--- @param symbol_positions { name: string, position: { line: number, character: number }, uri: string }[]
--- @param callback fun(types: _99.Lsp.ExternalType[])
function M.fetch_type_signatures(bufnr, symbol_positions, callback)
    if not symbol_positions or #symbol_positions == 0 then
        callback({})
        return
    end

    local hover = require("99.lsp.hover")
    local definitions = require("99.lsp.definitions")

    local results = {}
    local pending = #symbol_positions
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

    for _, sym_pos in ipairs(symbol_positions) do
        local file_path = vim.uri_to_fname(sym_pos.uri)
        definitions.ensure_buffer_loaded(file_path, function(target_bufnr, err)
            if err or not target_bufnr then
                check_done()
                return
            end

            hover.get_hover(target_bufnr, sym_pos.position, function(result, _)
                if result and result.contents then
                    local type_sig = hover.extract_type_for_external(result.contents)
                    if type_sig and type_sig ~= "" then
                        table.insert(results, {
                            symbol_name = sym_pos.name,
                            type_signature = type_sig,
                            package_name = M.extract_package_name(file_path),
                            uri = sym_pos.uri,
                            position = sym_pos.position,
                        })
                    end
                end
                check_done()
            end)
        end)
    end
end

--- Format external types for context output
--- @param types _99.Lsp.ExternalType[]
--- @return string
function M.format_external_types(types)
    if not types or #types == 0 then
        return ""
    end

    local by_package = {}
    for _, ext_type in ipairs(types) do
        local pkg = ext_type.package_name
        if not by_package[pkg] then
            by_package[pkg] = {}
        end
        table.insert(by_package[pkg], ext_type)
    end

    local parts = { "## External Types" }

    for pkg, pkg_types in pairs(by_package) do
        table.insert(parts, string.format("\n### %s", pkg))
        for _, ext_type in ipairs(pkg_types) do
            table.insert(
                parts,
                string.format("- %s: %s", ext_type.symbol_name, ext_type.type_signature)
            )
        end
    end

    return table.concat(parts, "\n")
end

--- Get external type information for a buffer (main entry point)
--- @param bufnr number Buffer number
--- @param cache _99.Lsp.Cache? Optional cache instance
--- @param callback fun(types: _99.Lsp.ExternalType[])
function M.get_external_types(bufnr, cache, callback)
    local lsp = require("99.lsp")
    local config = lsp.config

    M.identify_external_imports(bufnr, function(external_imports)
        if #external_imports == 0 then
            callback({})
            return
        end

        local symbol_positions = {}
        for _, imp in ipairs(external_imports) do
            if imp.resolved_uri and imp.position then
                for _, sym_name in ipairs(imp.symbols or {}) do
                    table.insert(symbol_positions, {
                        name = sym_name,
                        position = imp.position,
                        uri = imp.resolved_uri,
                    })
                end
            end
        end

        if cache then
            local cached_types = {}
            local uncached_positions = {}

            for _, sym_pos in ipairs(symbol_positions) do
                local cache_key = sym_pos.uri .. "#" .. sym_pos.name
                local entry = cache:get_if_valid(cache_key)
                if entry and entry.symbols then
                    for _, ext_type in ipairs(entry.symbols) do
                        table.insert(cached_types, ext_type)
                    end
                else
                    table.insert(uncached_positions, sym_pos)
                end
            end

            if #uncached_positions == 0 then
                callback(cached_types)
                return
            end

            M.fetch_type_signatures(bufnr, uncached_positions, function(new_types)
                for _, ext_type in ipairs(new_types) do
                    local cache_key = ext_type.uri .. "#" .. ext_type.symbol_name
                    cache:set_with_ttl(
                        cache_key,
                        { symbols = { ext_type } },
                        config.external_type_ttl
                    )
                end

                for _, t in ipairs(new_types) do
                    table.insert(cached_types, t)
                end
                callback(cached_types)
            end)
        else
            M.fetch_type_signatures(bufnr, symbol_positions, callback)
        end
    end)
end

return M
