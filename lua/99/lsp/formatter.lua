local M = {}

--- LSP SymbolKind constants (from LSP 3.17 specification)
--- @enum _99.Lsp.SymbolKind
M.SymbolKind = {
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

--- Reverse lookup table: kind number -> name
--- @type table<number, string>
M.SymbolKindName = {}
for name, num in pairs(M.SymbolKind) do
    M.SymbolKindName[num] = name
end

--- Symbols that should be displayed with block formatting (have children)
local BLOCK_KINDS = {
    [M.SymbolKind.Class] = true,
    [M.SymbolKind.Interface] = true,
    [M.SymbolKind.Struct] = true,
    [M.SymbolKind.Enum] = true,
    [M.SymbolKind.Module] = true,
    [M.SymbolKind.Namespace] = true,
}

--- Symbols that should be formatted as function signatures
local FUNCTION_KINDS = {
    [M.SymbolKind.Function] = true,
    [M.SymbolKind.Method] = true,
    [M.SymbolKind.Constructor] = true,
}

--- Get the display name for a SymbolKind
--- @param kind number LSP SymbolKind value
--- @return string Display name (lowercase)
function M.kind_to_string(kind)
    local name = M.SymbolKindName[kind]
    if name then
        return name:lower()
    end
    return "unknown"
end

--- Get a compact keyword for the symbol kind (for output)
--- @param kind number LSP SymbolKind value
--- @return string Compact keyword
function M.kind_to_keyword(kind)
    local keywords = {
        [M.SymbolKind.Class] = "class",
        [M.SymbolKind.Interface] = "interface",
        [M.SymbolKind.Struct] = "struct",
        [M.SymbolKind.Enum] = "enum",
        [M.SymbolKind.Function] = "fn",
        [M.SymbolKind.Method] = "",
        [M.SymbolKind.Constructor] = "constructor",
        [M.SymbolKind.Property] = "",
        [M.SymbolKind.Field] = "",
        [M.SymbolKind.Variable] = "",
        [M.SymbolKind.Constant] = "const",
        [M.SymbolKind.EnumMember] = "",
        [M.SymbolKind.Module] = "module",
        [M.SymbolKind.Namespace] = "namespace",
        [M.SymbolKind.TypeParameter] = "type",
    }
    return keywords[kind] or ""
end

--- Check if a symbol kind should be displayed as a block (with children)
--- @param kind number LSP SymbolKind value
--- @return boolean
function M.is_block_kind(kind)
    return BLOCK_KINDS[kind] == true
end

--- Check if a symbol kind is a function-like symbol
--- @param kind number LSP SymbolKind value
--- @return boolean
function M.is_function_kind(kind)
    return FUNCTION_KINDS[kind] == true
end

--- Create indentation string
--- @param level number Indentation level
--- @return string Indentation string (2 spaces per level)
local function indent(level)
    return string.rep("  ", level)
end

--- Format a single symbol to a compact string representation
--- @param symbol _99.Lsp.Symbol The symbol to format
--- @param indent_level number Current indentation level
--- @return string Formatted symbol line
function M.format_symbol(symbol, indent_level)
    indent_level = indent_level or 0
    local prefix = indent(indent_level)
    local keyword = M.kind_to_keyword(symbol.kind)

    -- Use signature if available, otherwise just the name
    local display = symbol.signature or symbol.name

    -- Add keyword prefix if present
    if keyword ~= "" then
        display = keyword .. " " .. display
    end

    return prefix .. display
end

--- Format a symbol with its children (for classes, interfaces, etc.)
--- @param symbol _99.Lsp.Symbol The symbol to format
--- @param indent_level number Current indentation level
--- @return string[] Lines of formatted output
function M.format_symbol_with_children(symbol, indent_level)
    indent_level = indent_level or 0
    local lines = {}
    local prefix = indent(indent_level)
    local keyword = M.kind_to_keyword(symbol.kind)

    -- Opening line
    local opening = prefix
    if keyword ~= "" then
        opening = opening .. keyword .. " "
    end
    opening = opening .. symbol.name .. " {"
    table.insert(lines, opening)

    -- Children
    if symbol.children and #symbol.children > 0 then
        for _, child in ipairs(symbol.children) do
            if M.is_block_kind(child.kind) then
                -- Recursively format nested blocks
                local child_lines = M.format_symbol_with_children(child, indent_level + 1)
                for _, line in ipairs(child_lines) do
                    table.insert(lines, line)
                end
            else
                -- Simple child symbol
                local child_line = M.format_symbol(child, indent_level + 1)
                table.insert(lines, child_line)
            end
        end
    end

    -- Closing brace
    table.insert(lines, prefix .. "}")

    return lines
end

--- Format a complete file's symbols for LLM context
--- @param file_path string The file path to display
--- @param symbols _99.Lsp.Symbol[] The symbols to format
--- @return string Complete formatted context string
function M.format_file_context(file_path, symbols)
    local lines = {}

    -- Header
    table.insert(lines, string.format("=== File: %s ===", file_path))
    table.insert(lines, "Symbols:")

    -- Format each top-level symbol
    for _, symbol in ipairs(symbols) do
        if M.is_block_kind(symbol.kind) then
            -- Block symbol with potential children
            local symbol_lines = M.format_symbol_with_children(symbol, 1)
            for _, line in ipairs(symbol_lines) do
                table.insert(lines, line)
            end
            table.insert(lines, "")
        else
            -- Simple symbol
            local line = M.format_symbol(symbol, 1)
            table.insert(lines, line)
        end
    end

    return table.concat(lines, "\n")
end

--- Format import context
--- @param imports _99.Lsp.Import[] The imports to format
--- @return string Formatted imports string
function M.format_imports(imports)
    if not imports or #imports == 0 then
        return ""
    end

    local lines = { "", "Imports:" }

    for _, import in ipairs(imports) do
        local line = "  from " .. import.module_path .. ": "

        if import.resolved_symbols and #import.resolved_symbols > 0 then
            -- Format resolved symbols
            local symbol_strs = {}
            for _, sym in ipairs(import.resolved_symbols) do
                table.insert(symbol_strs, sym.signature or sym.name)
            end
            line = line .. table.concat(symbol_strs, ", ")
        elseif import.symbols and #import.symbols > 0 then
            -- Just list unresolved symbol names
            line = line .. table.concat(import.symbols, ", ")
        end

        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

return M
