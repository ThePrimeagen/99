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
    local display = symbol.signature or symbol.name

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

    local opening = prefix
    if keyword ~= "" then
        opening = opening .. keyword .. " "
    end
    opening = opening .. symbol.name .. " {"
    table.insert(lines, opening)

    if symbol.children and #symbol.children > 0 then
        for _, child in ipairs(symbol.children) do
            if M.is_block_kind(child.kind) then
                local child_lines =
                    M.format_symbol_with_children(child, indent_level + 1)
                for _, line in ipairs(child_lines) do
                    table.insert(lines, line)
                end
            else
                local child_line = M.format_symbol(child, indent_level + 1)
                table.insert(lines, child_line)
            end
        end
    end

    table.insert(lines, prefix .. "}")

    return lines
end

--- Format a complete file's symbols for LLM context
--- @param file_path string The file path to display
--- @param symbols _99.Lsp.Symbol[] The symbols to format
--- @return string Complete formatted context string
function M.format_file_context(file_path, symbols)
    local lines = {}

    table.insert(lines, string.format("=== File: %s ===", file_path))
    table.insert(lines, "Symbols:")

    for _, symbol in ipairs(symbols) do
        if M.is_block_kind(symbol.kind) then
            local symbol_lines = M.format_symbol_with_children(symbol, 1)
            for _, line in ipairs(symbol_lines) do
                table.insert(lines, line)
            end
            table.insert(lines, "")
        else
            local line = M.format_symbol(symbol, 1)
            table.insert(lines, line)
        end
    end

    return table.concat(lines, "\n")
end

--- Severity level names for diagnostics
--- @type table<number, string>
local SEVERITY_NAMES = {
    [1] = "ERROR",
    [2] = "WARN",
    [3] = "INFO",
    [4] = "HINT",
}

--- Format a single diagnostic
--- @param diag _99.Lsp.Diagnostic
--- @return string Formatted diagnostic line
function M.format_diagnostic(diag)
    local severity = SEVERITY_NAMES[diag.severity] or "UNKNOWN"
    local location =
        string.format("%d:%d", (diag.lnum or 0) + 1, (diag.col or 0) + 1)

    local parts = { severity, location, diag.message or "" }

    if diag.source then
        table.insert(parts, 1, "[" .. diag.source .. "]")
    end

    if diag.code then
        table.insert(parts, "(" .. tostring(diag.code) .. ")")
    end

    return table.concat(parts, " ")
end

--- Format multiple diagnostics for context
--- @param diagnostics _99.Lsp.Diagnostic[] Diagnostics to format
--- @return string Formatted diagnostics string
function M.format_diagnostics(diagnostics)
    if not diagnostics or #diagnostics == 0 then
        return ""
    end

    local lines = { "", "Diagnostics:" }

    for _, diag in ipairs(diagnostics) do
        table.insert(lines, "  " .. M.format_diagnostic(diag))
    end

    return table.concat(lines, "\n")
end

--- InlayHintKind constants (LSP 3.17)
--- @enum _99.Lsp.InlayHintKind
M.InlayHintKind = {
    Type = 1,
    Parameter = 2,
}

--- Format inlay hints for context (LSP 3.17)
--- @param hints table[] LSP InlayHint array
--- @return string Formatted inlay hints string
function M.format_inlay_hints(hints)
    if not hints or #hints == 0 then
        return ""
    end

    local lines = { "", "Inlay Hints:" }

    for _, hint in ipairs(hints) do
        local label = ""
        if type(hint.label) == "string" then
            label = hint.label
        elseif type(hint.label) == "table" then
            local parts = {}
            for _, part in ipairs(hint.label) do
                if type(part) == "string" then
                    table.insert(parts, part)
                elseif part.value then
                    table.insert(parts, part.value)
                end
            end
            label = table.concat(parts, "")
        end

        if label ~= "" then
            local kind_str = ""
            if hint.kind == M.InlayHintKind.Type then
                kind_str = "type"
            elseif hint.kind == M.InlayHintKind.Parameter then
                kind_str = "param"
            end

            local pos = hint.position
            local location = ""
            if pos then
                location = string.format(
                    "%d:%d",
                    (pos.line or 0) + 1,
                    (pos.character or 0) + 1
                )
            end

            if kind_str ~= "" then
                table.insert(
                    lines,
                    string.format("  [%s] %s: %s", kind_str, location, label)
                )
            else
                table.insert(lines, string.format("  %s: %s", location, label))
            end
        end
    end

    if #lines <= 2 then
        return ""
    end

    return table.concat(lines, "\n")
end

return M
