--------------------------------------------------------------------------------
-- LSP Context Gathering Module
-- Provides LSP-based information gathering to improve LLM context
--------------------------------------------------------------------------------

local Logger = require("99.logger.logger")

--- @class LspPosition
--- @field character number Zero-based character offset within a line
--- @field line number Zero-based line number

--- @class LspRange
--- @field start LspPosition The start position of the range (inclusive)
--- @field end LspPosition The end position of the range (exclusive)

--- @class _99.lsp.SymbolInfo
--- @field name string The symbol name
--- @field type string? The type information from hover
--- @field signature string? Function signature if applicable

local M = {}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--- Makes an LSP textDocument/hover request for a given position.
---
--- @param bufnr number The buffer number
--- @param position LspPosition The position to hover at
--- @param cb fun(result: string|nil): nil Callback with hover text or nil
local function get_hover_text(bufnr, position, cb)
    local params = {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = position,
    }

    vim.lsp.buf_request(
        bufnr,
        "textDocument/hover",
        params,
        function(err, result)
            if err or not result or not result.contents then
                cb(nil)
                return
            end

            local content = result.contents
            local text

            if type(content) == "string" then
                text = content
            elseif type(content) == "table" then
                if content.value then
                    text = content.value
                elseif content.kind == "markdown" then
                    text = content.value or ""
                else
                    local parts = {}
                    for _, part in ipairs(content) do
                        if type(part) == "string" then
                            table.insert(parts, part)
                        elseif part.value then
                            table.insert(parts, part.value)
                        end
                    end
                    text = table.concat(parts, "\n")
                end
            end

            -- Clean up markdown fencing
            if text then
                text = text:gsub("```%w*\n?", ""):gsub("```", "")
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
            end

            cb(text)
        end
    )
end

--- Gets the LSP clients for a buffer.
---
--- @param bufnr number The buffer number
--- @return vim.lsp.Client[] List of LSP clients
local function get_lsp_clients(bufnr)
    return vim.lsp.get_clients({ bufnr = bufnr })
end

--- Checks if LSP is available for a buffer.
---
--- @param bufnr number The buffer number
--- @return boolean True if LSP is available
function M.has_lsp(bufnr)
    local clients = get_lsp_clients(bufnr)
    return #clients > 0
end

--------------------------------------------------------------------------------
-- IDENTIFIER EXTRACTION
--------------------------------------------------------------------------------

--- @class _99.lsp.Identifier
--- @field name string The identifier text
--- @field line number 0-based line number
--- @field col number 0-based column number

--- Extracts identifiers from a treesitter range that might need type info.
--- Focuses on function calls, method calls, and variable references.
---
--- @param buffer number The buffer number
--- @param range _99.Range The range to search within
--- @return _99.lsp.Identifier[] List of identifiers found
function M.extract_identifiers(buffer, range)
    local lang = vim.bo[buffer].ft
    local ok, parser = pcall(vim.treesitter.get_parser, buffer, lang)
    if not ok or not parser then
        return {}
    end

    local tree = parser:parse()[1]
    if not tree then
        return {}
    end

    local root = tree:root()
    local identifiers = {}
    local seen = {}

    -- Convert range to 0-based for treesitter
    local start_row = range.start.row - 1
    local end_row = range.stop.row - 1

    --- @param node TSNode
    local function collect_identifiers(node)
        local node_start_row, node_start_col, node_end_row, _ = node:range()

        -- Skip if outside our range
        if node_end_row < start_row or node_start_row > end_row then
            return
        end

        local node_type = node:type()

        -- Collect identifiers based on node type
        if
            node_type == "identifier"
            or node_type == "field_expression"
            or node_type == "method_index_expression"
        then
            local text = vim.treesitter.get_node_text(node, buffer)
            if text and not seen[text] then
                seen[text] = true
                table.insert(identifiers, {
                    name = text,
                    line = node_start_row,
                    col = node_start_col,
                })
            end
        end

        -- Recurse into children
        for child in node:iter_children() do
            collect_identifiers(child)
        end
    end

    collect_identifiers(root)
    return identifiers
end

--------------------------------------------------------------------------------
-- TYPE INFO GATHERING
--------------------------------------------------------------------------------

--- Gets type information for identifiers using LSP hover.
---
--- @param buffer number The buffer number
--- @param identifiers _99.lsp.Identifier[] List of identifiers to get info for
--- @param cb fun(results: table<string, string>): nil Callback with name -> type map
function M.get_type_info(buffer, identifiers, cb)
    if #identifiers == 0 then
        cb({})
        return
    end

    if not M.has_lsp(buffer) then
        cb({})
        return
    end

    local results = {}
    local pending = #identifiers

    for _, ident in ipairs(identifiers) do
        local position = { line = ident.line, character = ident.col }

        get_hover_text(buffer, position, function(hover_text)
            if hover_text and hover_text ~= "" then
                results[ident.name] = hover_text
            end

            pending = pending - 1
            if pending == 0 then
                cb(results)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- CONTEXT GENERATION
--------------------------------------------------------------------------------

--- Formats type information into a context string for LLM consumption.
---
--- @param type_info table<string, string> Map of symbol name to type info
--- @return string Formatted context string
function M.format_type_context(type_info)
    if not type_info or vim.tbl_isempty(type_info) then
        return ""
    end

    local lines = { "<TypeContext>" }

    for name, type_str in pairs(type_info) do
        -- Clean and format the type info
        local clean_type = type_str:gsub("\n", " "):gsub("%s+", " ")
        table.insert(lines, string.format("  %s: %s", name, clean_type))
    end

    table.insert(lines, "</TypeContext>")
    return table.concat(lines, "\n")
end

--- Gathers LSP context for a given range asynchronously.
--- This is the main entry point for getting type context for LLM requests.
---
--- @param context _99.RequestContext The request context
--- @param cb fun(context_str: string): nil Callback with formatted context
function M.gather_context(context, cb)
    local logger = Logger:set_area("lsp.gather_context")
    local buffer = context.buffer

    if not M.has_lsp(buffer) then
        logger:debug("No LSP available for buffer")
        cb("")
        return
    end

    if not context.range then
        logger:debug("No range specified in context")
        cb("")
        return
    end

    logger:debug("Extracting identifiers from range")
    local identifiers = M.extract_identifiers(buffer, context.range)

    if #identifiers == 0 then
        logger:debug("No identifiers found")
        cb("")
        return
    end

    logger:debug("Getting type info for identifiers", "count", #identifiers)
    M.get_type_info(buffer, identifiers, function(type_info)
        local formatted = M.format_type_context(type_info)
        logger:debug("Generated type context", "length", #formatted)
        cb(formatted)
    end)
end

--- Synchronous version that waits for LSP response.
--- Use with caution - may block for a short time.
---
--- @param context _99.RequestContext The request context
--- @param timeout_ms number? Timeout in milliseconds (default 1000)
--- @return string The formatted type context
function M.gather_context_sync(context, timeout_ms)
    timeout_ms = timeout_ms or 1000
    local result = ""
    local done = false

    M.gather_context(context, function(ctx)
        result = ctx
        done = true
    end)

    vim.wait(timeout_ms, function()
        return done
    end, 10)

    return result
end

return M
