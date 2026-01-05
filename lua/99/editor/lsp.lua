local logger = require("99.logger.logger")

--------------------------------------------------------------------------------
-- TYPE DEFINITIONS
--------------------------------------------------------------------------------
-- These types define the structure of data we work with when interacting
-- with Neovim's LSP client. They provide type safety and documentation
-- for the various LSP protocol structures we use.
--------------------------------------------------------------------------------

--- @class TextChangedIEvent
--- @field buf number The buffer number that changed
--- @field file string The file path of the changed buffer

--- @class LspPosition
--- @field character number Zero-based character offset within a line
--- @field line number Zero-based line number

--- @class LspRange
--- @field start LspPosition The start position of the range (inclusive)
--- @field end LspPosition The end position of the range (exclusive)

--- @class LspDefinitionResult
--- @field range LspRange The range in the target document where the definition is located
--- @field uri string The URI of the document containing the definition (e.g., "file:///path/to/file.lua")

--------------------------------------------------------------------------------
-- LSP SYMBOL KIND ENUMERATION
--------------------------------------------------------------------------------
-- The LSP protocol defines a standard set of symbol kinds that language servers
-- use to categorize symbols. This table maps the numeric values to human-readable
-- names for easier debugging and filtering.
--
-- Reference: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind
--------------------------------------------------------------------------------

--- @enum LspSymbolKind
local SymbolKind = {
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
    Object = 19,
    Key = 20,
    Null = 21,
    EnumMember = 22,
    Struct = 23,
    Event = 24,
    Operator = 25,
    TypeParameter = 26,
}

--- Reverse lookup table: maps numeric SymbolKind values back to their string names.
--- This is useful for logging and debugging purposes when you have a numeric kind
--- and want to display a human-readable name.
--- @type table<number, string>
local SymbolKindName = {}
for name, value in pairs(SymbolKind) do
    SymbolKindName[value] = name
end

--------------------------------------------------------------------------------
-- LSP DOCUMENT SYMBOL TYPES
--------------------------------------------------------------------------------
-- These types represent the structure of symbols returned by the LSP
-- textDocument/documentSymbol request. Document symbols can be hierarchical
-- (with children) representing the structure of the code.
--------------------------------------------------------------------------------

--- @class LspDocumentSymbol
--- @field name string The name of the symbol (e.g., function name, variable name)
--- @field kind number The kind of symbol (see SymbolKind enum above)
--- @field range LspRange The full range of the symbol including its body
--- @field selectionRange LspRange The range that should be selected when navigating to this symbol
--- @field detail? string Additional detail about the symbol (e.g., type signature)
--- @field children? LspDocumentSymbol[] Nested symbols (e.g., methods within a class)

--- @class LspSymbolInformation
--- @field name string The name of the symbol
--- @field kind number The kind of symbol (see SymbolKind enum)
--- @field location { uri: string, range: LspRange } The location where the symbol is defined
--- @field containerName? string The name of the containing symbol (e.g., class name for a method)

--------------------------------------------------------------------------------
-- EXPORT SYMBOL TYPES
--------------------------------------------------------------------------------
-- These types represent the processed/normalized export information that
-- we extract from LSP responses. They provide a cleaner interface for
-- consumers of this module.
--------------------------------------------------------------------------------

--- @class ExportedSymbol
--- @field name string The name of the exported symbol
--- @field kind number The LSP SymbolKind value
--- @field kind_name string Human-readable name of the symbol kind
--- @field range LspRange The range where the symbol is defined
--- @field detail? string Additional detail (e.g., type information if available)
--- @field children? ExportedSymbol[] Nested symbols (for classes/modules with members)

--- @class ModuleExports
--- @field uri string The URI of the module file
--- @field module_path string The original require path (e.g., "99.logger.logger")
--- @field symbols ExportedSymbol[] All exported symbols from the module
--- @field error? string Error message if the operation failed

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--- Converts a Treesitter node's position to an LSP-compatible position.
--- Treesitter and LSP both use 0-based line numbers, but this function
--- ensures we extract the correct start position from a TS node.
---
--- @param node _99.treesitter.Node The treesitter node to convert
--- @return LspPosition The LSP-compatible position (0-based line and character)
local function ts_node_to_lsp_position(node)
    -- Treesitter's range() returns: start_row, start_col, end_row, end_col (all 0-based)
    local start_row, start_col, _, _ = node:range()
    return { line = start_row, character = start_col }
end

--- Makes an LSP textDocument/definition request for a given position.
--- This is used to jump from a require() call to the actual module file.
---
--- @param buffer number The buffer number to make the request for
--- @param position LspPosition The position in the document to get definitions for
--- @param cb fun(res: LspDefinitionResult[] | nil): nil Callback receiving the definition results
local function get_lsp_definitions(buffer, position, cb)
    -- make_position_params() creates the standard LSP position parameters
    -- including the textDocument identifier for the current buffer
    local params = vim.lsp.util.make_position_params()
    params.position = position

    -- buf_request sends an async request to all LSP servers attached to the buffer
    -- The "textDocument/definition" method returns the location(s) where a symbol is defined
    vim.lsp.buf_request(
        buffer,
        "textDocument/definition",
        params,
        function(_, result, _, _)
            cb(result)
        end
    )
end

--- Resolves a Lua require path to an absolute file path using Neovim's runtime.
--- This uses vim.api.nvim_get_runtime_file which searches all runtimepath entries.
---
--- Example: "99.logger.logger" resolves to "/path/to/plugin/lua/99/logger/logger.lua"
---
--- @param require_path string The Lua require path (e.g., "99.logger.logger")
--- @return string|nil The absolute file path, or nil if it can't be resolved
local function resolve_require_path(require_path)
    -- Convert dot notation to path separators for runtime file lookup
    -- e.g., "99.logger.logger" -> "lua/99/logger/logger.lua"
    local relative_path = "lua/" .. require_path:gsub("%.", "/") .. ".lua"

    -- nvim_get_runtime_file searches all directories in 'runtimepath'
    -- The second argument (false) means return only the first match
    local results = vim.api.nvim_get_runtime_file(relative_path, false)

    if results and #results > 0 then
        return results[1]
    end

    -- Also try init.lua for module directories
    -- e.g., require("99.logger") might resolve to "lua/99/logger/init.lua"
    local init_path = "lua/" .. require_path:gsub("%.", "/") .. "/init.lua"
    results = vim.api.nvim_get_runtime_file(init_path, false)

    if results and #results > 0 then
        return results[1]
    end

    return nil
end

--- Converts a top-level LSP DocumentSymbol to our ExportedSymbol format.
--- Only converts the symbol itself, not its internal children (those are implementation details).
--- For classes/tables, we include direct method/field children but not their internals.
---
--- @param lsp_symbol LspDocumentSymbol The LSP symbol to convert
--- @return ExportedSymbol The normalized exported symbol
local function convert_to_exported_symbol(lsp_symbol)
    local exported = {
        name = lsp_symbol.name,
        kind = lsp_symbol.kind,
        kind_name = SymbolKindName[lsp_symbol.kind] or "Unknown",
        range = lsp_symbol.range,
        detail = lsp_symbol.detail,
    }

    -- For classes/objects, include direct children (methods, fields) but not their internals
    -- This gives us the public API without implementation details
    if lsp_symbol.children and #lsp_symbol.children > 0 then
        -- Only include Method and Field children (the public interface)
        local dominated_kinds = {
            [SymbolKind.Method] = true,
            [SymbolKind.Field] = true,
            [SymbolKind.Function] = true,
            [SymbolKind.Property] = true,
            [SymbolKind.Constant] = true,
        }

        exported.children = {}
        for _, child in ipairs(lsp_symbol.children) do
            if dominated_kinds[child.kind] then
                -- Only include the child's signature, not its internals
                table.insert(exported.children, {
                    name = child.name,
                    kind = child.kind,
                    kind_name = SymbolKindName[child.kind] or "Unknown",
                    range = child.range,
                    detail = child.detail,
                })
            end
        end

        -- If no relevant children, remove the empty table
        if #exported.children == 0 then
            exported.children = nil
        end
    end

    return exported
end

--- Flattens a hierarchical symbol tree into a flat list.
--- Useful when you want all symbols regardless of nesting level.
---
--- @param symbols ExportedSymbol[] The hierarchical symbol list
--- @param result? ExportedSymbol[] Accumulator for recursive calls (internal use)
--- @return ExportedSymbol[] Flat list of all symbols
local function flatten_symbols(symbols, result)
    result = result or {}
    for _, symbol in ipairs(symbols) do
        -- Add the symbol without its children to the flat list
        local flat_symbol = {
            name = symbol.name,
            kind = symbol.kind,
            kind_name = symbol.kind_name,
            range = symbol.range,
            detail = symbol.detail,
        }
        table.insert(result, flat_symbol)

        -- Recursively flatten children
        if symbol.children then
            flatten_symbols(symbol.children, result)
        end
    end
    return result
end

--- Extracts the type annotation from the line above a symbol's definition.
--- Looks for LuaDoc-style annotations like `--- @param`, `--- @return`, `--- @class`, etc.
---
--- @param lines string[] The file contents as an array of lines
--- @param start_line number The 0-based line number where the symbol starts
--- @return string|nil The extracted type annotation or nil if none found
local function extract_type_annotation(lines, start_line)
    -- Look at lines above the symbol for type annotations
    -- We search upward until we find a non-comment line or reach the start
    local annotations = {}
    local i = start_line -- 0-based, so this is the line before in 1-based

    while i >= 1 do
        local line = lines[i] -- lines array is 1-based
        if not line then
            break
        end

        -- Check if it's a LuaDoc comment
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed:match("^%-%-%-") then
            -- It's a doc comment, extract the content
            table.insert(annotations, 1, trimmed)
            i = i - 1
        elseif trimmed:match("^%-%-") then
            -- Regular comment, might still be relevant
            i = i - 1
        else
            -- Non-comment line, stop searching
            break
        end
    end

    if #annotations > 0 then
        return table.concat(annotations, "\n")
    end
    return nil
end

--- Extracts simple enum/constant values from a table definition.
--- For tables like `local SymbolKind = { File = 1, Module = 2 }`, extracts the key-value pairs.
---
--- @param lines string[] The file contents as an array of lines
--- @param start_line number The 0-based line number where the table starts
--- @param end_line number The 0-based line number where the table ends
--- @return table<string, string>|nil Map of field names to values, or nil if not a simple table
local function extract_table_values(lines, start_line, end_line)
    local values = {}
    -- Convert to 1-based for lines array access
    for i = start_line + 1, end_line + 1 do
        local line = lines[i]
        if line then
            -- Match patterns like "Field = value," or "Field = value"
            local key, value = line:match("%s*([%w_]+)%s*=%s*([^,]+),?")
            if key and value then
                values[key] = value:match("^%s*(.-)%s*$") -- trim whitespace
            end
        end
    end

    if next(values) then
        return values
    end
    return nil
end

--------------------------------------------------------------------------------
-- LSP CLASS
--------------------------------------------------------------------------------
-- The main Lsp class provides methods for interacting with Neovim's LSP client.
-- It handles definition lookups, symbol retrieval, and module export extraction.
--------------------------------------------------------------------------------

--- @class Lsp
--- @field config _99.Options Configuration options for the LSP client
local Lsp = {}
Lsp.__index = Lsp

--- Creates a new Lsp instance with the given configuration.
---
--- @param config _99.Options The configuration options
--- @return Lsp A new Lsp instance
function Lsp:new(config)
    return setmetatable({
        config = config,
    }, self)
end

--- Gets the LSP definition for a Treesitter node.
--- This is useful for jumping from a symbol usage to its definition.
---
--- @param buffer number The buffer containing the node
--- @param node _99.treesitter.Node The treesitter node to get the definition for
--- @param cb fun(res: LspDefinitionResult | nil): nil Callback receiving the definition result
function Lsp.get_ts_node_definition(buffer, node, cb)
    local range = ts_node_to_lsp_position(node)
    get_lsp_definitions(buffer, range, cb)
end

--------------------------------------------------------------------------------
-- MODULE EXPORT EXTRACTION
--------------------------------------------------------------------------------
-- These functions handle the extraction of exported symbols from a Lua module.
-- The process involves:
-- 1. Resolving the require path to a file URI (via LSP definition lookup)
-- 2. Requesting document symbols from the target file's LSP server
-- 3. Processing and normalizing the symbol information
--------------------------------------------------------------------------------

--- Ensures a buffer is loaded and has LSP attached, then calls the callback.
--- This handles the async nature of LSP attachment.
---
--- @param filepath string The file path to load
--- @param cb fun(bufnr: number|nil, err: string|nil): nil Callback with buffer number or error
local function ensure_buffer_with_lsp(filepath, cb)
    -- Find existing buffer or create a new one for the file
    local bufnr = vim.fn.bufnr(filepath)

    if bufnr == -1 then
        -- Create a new buffer for the file without displaying it
        bufnr = vim.fn.bufadd(filepath)
    end

    -- Ensure the buffer is loaded (file contents read into memory)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        vim.fn.bufload(bufnr)
    end

    -- Wait for LSP to attach and index the buffer
    vim.defer_fn(function()
        local clients = vim.lsp.get_clients({ bufnr = bufnr })
        if #clients == 0 then
            cb(nil, "No LSP client attached to buffer for: " .. filepath)
            return
        end
        cb(bufnr, nil)
    end, 100)
end

--- Makes an LSP textDocument/hover request for a given position.
--- Returns type information and documentation for the symbol at that position.
---
--- @param bufnr number The buffer number
--- @param position LspPosition The position to hover at
--- @param cb fun(result: table|nil, err: string|nil): nil Callback with hover result
local function get_lsp_hover(bufnr, position, cb)
    local params = {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = position,
    }

    vim.lsp.buf_request(
        bufnr,
        "textDocument/hover",
        params,
        function(err, result, _, _)
            if err then
                cb(nil, vim.inspect(err))
                return
            end
            cb(result, nil)
        end
    )
end

--- Finds the return statement in a Lua file and extracts the exported keys.
--- Looks for patterns like `return { Foo = Foo, Bar = Bar }` or `return M`
---
--- @param bufnr number The buffer number
--- @return { name: string, line: number, col: number }[] List of exported names with positions
local function find_export_keys(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local exports = {}

    -- Find the last return statement (Lua modules typically end with return)
    local return_line_idx = nil
    for i = #lines, 1, -1 do
        if lines[i]:match("^%s*return%s+") then
            return_line_idx = i
            break
        end
    end

    if not return_line_idx then
        return exports
    end

    -- Collect all lines from return statement to end of file (handles multi-line returns)
    local return_text = ""
    for i = return_line_idx, #lines do
        return_text = return_text .. lines[i] .. "\n"
    end

    -- Check if it's a simple `return M` style
    local simple_return =
        lines[return_line_idx]:match("^%s*return%s+([%w_]+)%s*$")
    if simple_return then
        -- Find where this variable is defined and get its members
        -- For now, just return the module table name itself
        local col = lines[return_line_idx]:find(simple_return)
        table.insert(exports, {
            name = simple_return,
            line = return_line_idx - 1, -- 0-based
            col = col - 1, -- 0-based
        })
        return exports
    end

    -- Parse `return { Key = Value, ... }` style
    -- Find each key in the return table on the return line and subsequent lines
    for i = return_line_idx, #lines do
        local line = lines[i]
        -- Match patterns like "Key = " at the start of assignments in the table
        for key, col_start in line:gmatch("()([%w_]+)%s*=") do
            -- col_start is the position before the key, key is the actual key name
            -- Swap them since gmatch returns captures in order
            key, col_start = col_start, key
            if key ~= "" and not key:match("^%d") then
                table.insert(exports, {
                    name = key,
                    line = i - 1, -- 0-based
                    col = col_start - 1, -- 0-based
                })
            end
        end
    end

    return exports
end

--- Gets the hover information for each exported symbol using LSP.
--- This gives us the actual type information from the language server.
---
--- @param bufnr number The buffer number
--- @param export_keys { name: string, line: number, col: number }[] The export positions
--- @param cb fun(results: table<string, string>): nil Callback with name -> hover info map
local function get_exports_hover_info(bufnr, export_keys, cb)
    if #export_keys == 0 then
        cb({})
        return
    end

    local results = {}
    local pending = #export_keys

    for _, export in ipairs(export_keys) do
        -- Position cursor after the "=" to hover on the value being exported
        -- First, get the line to find where the value starts
        local line_text = vim.api.nvim_buf_get_lines(
            bufnr,
            export.line,
            export.line + 1,
            false
        )[1]

        -- Find the position after "Key = " to hover on the value
        local pattern = export.name .. "%s*=%s*()"
        local value_start = line_text:match(pattern)

        local hover_col = value_start and (value_start - 1) or export.col

        local position = { line = export.line, character = hover_col }

        get_lsp_hover(bufnr, position, function(result, _)
            if result and result.contents then
                -- Extract the markdown content from hover result
                local content = result.contents
                if type(content) == "table" then
                    if content.value then
                        results[export.name] = content.value
                    elseif content.kind == "markdown" then
                        results[export.name] = content.value
                    else
                        -- Array of MarkedString
                        local parts = {}
                        for _, part in ipairs(content) do
                            if type(part) == "string" then
                                table.insert(parts, part)
                            elseif part.value then
                                table.insert(parts, part.value)
                            end
                        end
                        results[export.name] = table.concat(parts, "\n")
                    end
                else
                    results[export.name] = tostring(content)
                end
            else
                results[export.name] = "unknown"
            end

            pending = pending - 1
            if pending == 0 then
                cb(results)
            end
        end)
    end
end

--- Extracts all exported symbols from a Lua module given its require path.
---
--- This is the main entry point for getting module exports. It works by:
--- 1. Resolving the require path to a file
--- 2. Finding the return statement to identify what's exported
--- 3. Using textDocument/hover on each export to get type information from LSP
---
--- Example usage:
---   Lsp.get_module_exports(bufnr, "99.logger.logger", function(exports)
---     for name, type_info in pairs(exports.symbols) do
---       print(name, type_info)
---     end
---   end)
---
--- @param _buffer number The current buffer (reserved for future LSP-based resolution)
--- @param require_path string The Lua require path (e.g., "99", "99.logger.logger")
--- @param cb fun(exports: ModuleExports): nil Callback receiving the module exports
function Lsp.get_module_exports(_buffer, require_path, cb)
    -- Resolve the module path using Neovim's runtimepath
    local resolved_path = resolve_require_path(require_path)

    if not resolved_path then
        cb({
            uri = "",
            module_path = require_path,
            symbols = {},
            error = "Could not resolve module path: "
                .. require_path
                .. ". The module may not be in runtimepath or may be a built-in module.",
        })
        return
    end

    local uri = vim.uri_from_fname(resolved_path)

    -- Load the buffer and wait for LSP
    ensure_buffer_with_lsp(resolved_path, function(bufnr, err)
        if err then
            cb({
                uri = uri,
                module_path = require_path,
                symbols = {},
                error = err,
            })
            return
        end

        -- Find the export keys from the return statement
        local export_keys = find_export_keys(bufnr)

        if #export_keys == 0 then
            cb({
                uri = uri,
                module_path = require_path,
                symbols = {},
                error = "No exports found in return statement",
            })
            return
        end

        -- Get hover information for each export using LSP
        get_exports_hover_info(bufnr, export_keys, function(hover_results)
            -- Convert to our symbol format
            local symbols = {}
            for _, export in ipairs(export_keys) do
                local hover_info = hover_results[export.name] or "unknown"
                table.insert(symbols, {
                    name = export.name,
                    kind = SymbolKind.Variable, -- Will be refined by hover info
                    kind_name = "Variable",
                    range = {
                        start = { line = export.line, character = export.col },
                        ["end"] = { line = export.line, character = export.col },
                    },
                    detail = hover_info,
                })
            end

            cb({
                uri = uri,
                module_path = require_path,
                symbols = symbols,
            })
        end)
    end)
end

--- Convenience function to get module exports synchronously using coroutines.
--- This wraps the async get_module_exports in a coroutine-friendly interface.
---
--- Note: This must be called from within a coroutine context.
---
--- Example:
---   local co = coroutine.create(function()
---     local exports = Lsp.get_module_exports_sync(bufnr, "99.logger.logger")
---     print(vim.inspect(exports))
---   end)
---   coroutine.resume(co)
---
--- @param buffer number The current buffer
--- @param require_path string The Lua require path
--- @return ModuleExports The module exports (blocks until complete)
function Lsp.get_module_exports_sync(buffer, require_path)
    local co = coroutine.running()
    if not co then
        error("get_module_exports_sync must be called from within a coroutine")
    end

    local result
    Lsp.get_module_exports(buffer, require_path, function(exports)
        result = exports
        -- Resume the coroutine that's waiting for this result
        if coroutine.status(co) == "suspended" then
            coroutine.resume(co)
        end
    end)

    -- Yield until the callback resumes us
    if not result then
        coroutine.yield()
    end

    return result
end

--- Gets a flat list of all symbols from a module (no hierarchy).
--- This is useful when you just want a simple list of all exported names
--- without caring about the nesting structure.
---
--- @param buffer number The current buffer
--- @param require_path string The Lua require path
--- @param cb fun(symbols: ExportedSymbol[], err: string|nil): nil Callback with flat symbol list
function Lsp.get_module_exports_flat(buffer, require_path, cb)
    Lsp.get_module_exports(buffer, require_path, function(exports)
        if exports.error then
            cb({}, exports.error)
            return
        end

        local flat = flatten_symbols(exports.symbols)
        cb(flat, nil)
    end)
end

--- Filters exported symbols by their kind.
--- Useful for getting only functions, or only variables, etc.
---
--- @param symbols ExportedSymbol[] The symbols to filter
--- @param kinds number[] List of SymbolKind values to include
--- @return ExportedSymbol[] Filtered list of symbols
function Lsp.filter_symbols_by_kind(symbols, kinds)
    -- Create a set for O(1) lookup
    local kind_set = {}
    for _, kind in ipairs(kinds) do
        kind_set[kind] = true
    end

    local filtered = {}
    for _, symbol in ipairs(symbols) do
        if kind_set[symbol.kind] then
            table.insert(filtered, symbol)
        end
    end

    return filtered
end

--- Gets only function exports from a module.
--- This is a convenience wrapper around get_module_exports_flat with filtering.
---
--- @param buffer number The current buffer
--- @param require_path string The Lua require path
--- @param cb fun(functions: ExportedSymbol[], err: string|nil): nil Callback with function symbols
function Lsp.get_module_functions(buffer, require_path, cb)
    Lsp.get_module_exports_flat(buffer, require_path, function(symbols, err)
        if err then
            cb({}, err)
            return
        end

        local functions = Lsp.filter_symbols_by_kind(symbols, {
            SymbolKind.Function,
            SymbolKind.Method,
        })
        cb(functions, nil)
    end)
end

--- Cleans up LSP hover output by removing markdown fencing and formatting
--- into a TypeScript-like type representation.
---
--- @param hover_text string The raw hover text from LSP
--- @return string The cleaned and formatted type information
local function format_hover_output(hover_text)
    if not hover_text or hover_text == "unknown" then
        return "unknown"
    end

    local lines = {}
    local in_code_block = false

    for line in hover_text:gmatch("[^\n]+") do
        -- Skip markdown code fence markers
        if line:match("^```") then
            in_code_block = not in_code_block
        else
            -- Clean up the line
            local cleaned = line
            -- Remove "local " prefix as it's not relevant for exports
            cleaned = cleaned:gsub("^local%s+", "")
            -- Remove variable name prefix like "SymbolKind: " since we show it separately
            cleaned = cleaned:gsub("^[%w_]+:%s*", "")
            if cleaned ~= "" then
                table.insert(lines, cleaned)
            end
        end
    end

    return table.concat(lines, "\n")
end

--- Finds all method/field definitions for a class in the source file.
--- Returns the line numbers where each member is defined so we can hover on them.
---
--- @param file_lines string[] The file contents
--- @param class_name string The name of the class (e.g., "Lsp")
--- @return { name: string, line: number, col: number }[] List of member positions
local function find_class_member_positions(file_lines, class_name)
    local members = {}

    for i, line in ipairs(file_lines) do
        -- Match function definitions like "function Lsp:method(" or "function Lsp.method("
        local method_name =
            line:match("^%s*function%s+" .. class_name .. "[%.:]([%w_]+)%s*%(")
        if method_name then
            -- Find the column where the method name starts
            local col = line:find(method_name, 1, true)
            table.insert(members, {
                name = method_name,
                line = i - 1, -- 0-based for LSP
                col = col and (col - 1) or 0,
            })
        end

        -- Also match field assignments like "Lsp.field = value" or "Lsp.__index = Lsp"
        local field_name = line:match("^%s*" .. class_name .. "%.([%w_]+)%s*=")
        if field_name and not line:match("^%s*function") then
            local col = line:find(field_name, 1, true)
            table.insert(members, {
                name = field_name,
                line = i - 1,
                col = col and (col - 1) or 0,
            })
        end
    end

    return members
end

--- Gets hover information for each class member using LSP.
--- This retrieves full type signatures from the language server.
---
--- @param bufnr number The buffer number
--- @param member_positions { name: string, line: number, col: number }[] Member positions
--- @param cb fun(results: table<string, string>): nil Callback with name -> type info map
local function get_class_members_hover(bufnr, member_positions, cb)
    if #member_positions == 0 then
        cb({})
        return
    end

    local results = {}
    local pending = #member_positions

    for _, member in ipairs(member_positions) do
        local position = { line = member.line, character = member.col }

        get_lsp_hover(bufnr, position, function(result, _)
            local hover_text = "unknown"

            if result and result.contents then
                local content = result.contents

                if type(content) == "table" then
                    if content.value then
                        hover_text = content.value
                    elseif content.kind then
                        hover_text = content.value or ""
                    else
                        local parts = {}
                        for _, part in ipairs(content) do
                            if type(part) == "string" then
                                table.insert(parts, part)
                            elseif part.value then
                                table.insert(parts, part.value)
                            end
                        end
                        hover_text = table.concat(parts, "\n")
                    end
                else
                    hover_text = tostring(content)
                end
            end

            results[member.name] = hover_text

            pending = pending - 1
            if pending == 0 then
                cb(results)
            end
        end)
    end
end

--- Formats a function hover result into TypeScript-style signature.
--- Extracts parameter types and return type from the hover markdown.
---
--- @param hover_text string The hover text from LSP
--- @return string The formatted signature like "fn(a: number, b: string): boolean"
local function format_function_signature(hover_text)
    -- Remove markdown code fences
    local clean = hover_text:gsub("```%w*\n?", ""):gsub("```", "")
    clean = clean:gsub("^%s*", ""):gsub("%s*$", "")

    -- Try to extract function signature from lua_ls format
    -- Format is typically: "function ClassName.method(param1: type1, param2: type2): returntype"
    -- or "function (param1: type1): returntype"
    local sig = clean:match("function%s*[%w_%.%:]*%((.-)%)%s*:%s*([^\n]+)")
        or clean:match("function%s*[%w_%.%:]*%((.-)%)")

    if sig then
        local params, ret =
            clean:match("function%s*[%w_%.%:]*%((.-)%)%s*:%s*([^\n]+)")
        if params then
            return string.format("(%s): %s", params, ret or "nil")
        else
            params = clean:match("function%s*[%w_%.%:]*%((.-)%)")
            return string.format("(%s): nil", params or "")
        end
    end

    -- Fallback: just return cleaned hover
    return clean
end

--- Parses an enum hover output and extracts all values (not truncated).
---
--- @param _hover_text string The hover text for an enum (unused, we read from source)
--- @param _bufnr number The buffer number (unused, for future use)
--- @param file_lines string[] The file contents
--- @param symbol_name string The name of the enum symbol
--- @return string[] Array of enum entries
local function expand_enum_values(_hover_text, _bufnr, file_lines, symbol_name)
    local values = {}

    -- Find the enum definition in the source file
    for i, line in ipairs(file_lines) do
        -- Look for the start of the enum definition
        if
            line:match("local%s+" .. symbol_name .. "%s*=")
            or line:match(symbol_name .. "%s*=%s*{")
        then
            -- Found it, now collect all key = value pairs until closing brace
            local j = i
            while j <= #file_lines do
                local enum_line = file_lines[j]

                -- Check for closing brace
                if enum_line:match("^%s*}") then
                    break
                end

                -- Extract key = value pairs
                local key, value = enum_line:match("^%s*([%w_]+)%s*=%s*([^,]+)")
                if key and value then
                    value = value:match("^%s*(.-)%s*,?%s*$") -- trim
                    table.insert(values, key .. " = " .. value)
                end

                j = j + 1
            end
            break
        end
    end

    return values
end

--- Pretty prints module exports for debugging purposes.
--- Shows the exported symbols with their type information from LSP hover.
--- Formats output in a TypeScript-like style for clarity.
--- This version expands classes by making additional LSP hover requests
--- for each class member to get full type signatures.
---
--- @param exports ModuleExports The exports to print
function Lsp.print_module_exports(exports)
    if exports.error then
        print("Error: " .. exports.error)
        return
    end

    -- Read source file for expanding types
    local filepath = vim.uri_to_fname(exports.uri)
    local file_lines = vim.fn.readfile(filepath)
    local bufnr = vim.fn.bufnr(filepath)

    -- Collect all classes that need member expansion
    local classes_to_expand = {}
    for _, symbol in ipairs(exports.symbols) do
        local hover = symbol.detail or "unknown"
        local is_class = hover:match("__index") ~= nil
            or hover:match(":%s*[%w_]+%s*{") ~= nil

        if is_class then
            local member_positions =
                find_class_member_positions(file_lines, symbol.name)
            if #member_positions > 0 then
                table.insert(classes_to_expand, {
                    symbol = symbol,
                    positions = member_positions,
                })
            end
        end
    end

    -- If no classes need expansion, print immediately
    if #classes_to_expand == 0 then
        Lsp._print_exports_sync(exports, file_lines, bufnr, {})
        return
    end

    -- Get hover info for all class members asynchronously
    local pending = #classes_to_expand
    local all_member_hovers = {}

    for _, class_info in ipairs(classes_to_expand) do
        get_class_members_hover(
            bufnr,
            class_info.positions,
            function(member_hovers)
                all_member_hovers[class_info.symbol.name] = member_hovers
                pending = pending - 1

                if pending == 0 then
                    -- All hovers complete, now print
                    Lsp._print_exports_sync(
                        exports,
                        file_lines,
                        bufnr,
                        all_member_hovers
                    )
                end
            end
        )
    end
end

--- Internal function to print exports after all async hover requests complete.
---
--- @param exports ModuleExports The exports to print
--- @param file_lines string[] The source file lines
--- @param bufnr number The buffer number
--- @param class_member_hovers table<string, table<string, string>> Class name -> member hovers
function Lsp._print_exports_sync(
    exports,
    file_lines,
    bufnr,
    class_member_hovers
)
    local out = {}

    table.insert(out, "Module: " .. exports.module_path)
    table.insert(out, "URI: " .. exports.uri)
    table.insert(out, string.rep("-", 60))

    for _, symbol in ipairs(exports.symbols) do
        table.insert(out, "")

        local hover = symbol.detail or "unknown"

        -- Detect what kind of export this is based on hover content
        local is_enum = hover:match("enum%s+") ~= nil
        local is_class = hover:match("__index") ~= nil
            or hover:match(":%s*[%w_]+%s*{") ~= nil

        if is_enum then
            -- Expand enum to show all values from source
            local values =
                expand_enum_values(hover, bufnr, file_lines, symbol.name)
            if #values > 0 then
                table.insert(out, symbol.name .. " = {")
                for _, v in ipairs(values) do
                    table.insert(out, "  " .. v)
                end
                table.insert(out, "}")
            else
                table.insert(
                    out,
                    symbol.name .. ": " .. format_hover_output(hover)
                )
            end
        elseif is_class then
            -- Use the pre-fetched member hovers
            local member_hovers = class_member_hovers[symbol.name] or {}
            table.insert(out, symbol.name .. " {")

            -- Also get field from the class annotation (@field config)
            local class_fields = {}
            for line in hover:gmatch("[^\n]+") do
                local field_name, field_type =
                    line:match("^%s*([%w_]+):%s*([^,}]+)")
                if field_name and field_type then
                    field_type = field_type:match("^%s*(.-)%s*,?$")
                    if field_type ~= "function" then
                        class_fields[field_name] = field_type
                    end
                end
            end

            -- Print fields first
            for field_name, field_type in pairs(class_fields) do
                if field_name ~= "__index" then
                    table.insert(out, "  " .. field_name .. ": " .. field_type)
                end
            end

            -- Print methods with full signatures from hover
            for method_name, method_hover in pairs(member_hovers) do
                if method_name ~= "__index" then
                    local sig = format_function_signature(method_hover)
                    table.insert(out, "  " .. method_name .. sig)
                end
            end

            table.insert(out, "}")
        else
            -- Simple type, just format it
            local formatted = format_hover_output(hover)
            table.insert(out, symbol.name .. ": " .. formatted)
        end
    end

    print(table.concat(out, "\n"))
end

--------------------------------------------------------------------------------
-- MODULE EXPORTS
--------------------------------------------------------------------------------
-- We export the Lsp class and related utilities for use by other modules.
-- The SymbolKind enum is also exported for filtering operations.
--------------------------------------------------------------------------------

-- Only run debug export if LSP is actually attached
vim.defer_fn(function()
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if #clients > 0 then
        Lsp.get_module_exports(bufnr, "99.editor.lsp", function(exports)
            Lsp.print_module_exports(exports)
        end)
    end
end, 200)

return {
    Lsp = Lsp,
    SymbolKind = SymbolKind,
    SymbolKindName = SymbolKindName,
}
