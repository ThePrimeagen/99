local geo = require("99.geo")
local Logger = require("99.logger.logger")
local Range = geo.Range

--- @class _99.treesitter.TSNode
--- @field start fun(): number
--- @field end_ fun(): number

--- @class _99.treesitter.Node
--- @field start fun(self: _99.treesitter.Node): number, number, number
--- @field end_ fun(self: _99.treesitter.Node): number, number, number
--- @field named fun(self: _99.treesitter.Node): boolean
--- @field type fun(self: _99.treesitter.Node): string
--- @field range fun(self: _99.treesitter.Node): number, number, number, number

local M = {}

local function_query = "99-function"
local imports_query = "99-imports"
local fn_call_query = "99-fn-call"
local comments_query = "99-comments"
local context_query = "99-context"
local includes_query = "99-includes"

--- @param buffer number
---@param lang string
local function tree_root(buffer, lang)
    -- Load the parser and the query.
    local ok, parser = pcall(vim.treesitter.get_parser, buffer, lang)
    if not ok then
        return nil
    end

    local tree = parser:parse()[1]
    return tree:root()
end

--- @param context _99.RequestContext
--- @param cursor _99.Point
--- @return _99.treesitter.TSNode | nil
function M.fn_call(context, cursor)
    local buffer = context.buffer
    local lang = context.file_type
    local logger = context.logger:set_area("treesitter")
    local root = tree_root(buffer, lang)
    if not root then
        Logger:error(
            "unable to find treeroot, this should never happen",
            "buffer",
            buffer,
            "lang",
            lang
        )
        return nil
    end

    local ok, query = pcall(vim.treesitter.query.get, lang, fn_call_query)
    if not ok or query == nil then
        logger:error(
            "unable to get the fn_call_query",
            "lang",
            lang,
            "buffer",
            buffer,
            "ok",
            type(ok),
            "query",
            type(query)
        )
        return nil
    end

    --- likely something that needs to be done with treesitter#get_node
    local found = nil
    for _, match, _ in query:iter_matches(root, buffer, 0, -1, { all = true }) do
        for _, nodes in pairs(match) do
            for _, node in ipairs(nodes) do
                local range = Range:from_ts_node(node, buffer)
                if range:contains(cursor) then
                    found = node
                    goto end_of_loops
                end
            end
        end
    end
    ::end_of_loops::

    logger:debug("treesitter#fn_call", "found", found ~= nil)

    return found
end

--- @class _99.treesitter.Function
--- @field function_range _99.Range
--- @field function_node _99.treesitter.TSNode
--- @field body_range _99.Range
--- @field body_node _99.treesitter.TSNode
local Function = {}
Function.__index = Function

--- uses the function_node to replace the text within vim using nvim_buf_set_text
--- to replace at the exact function begin / end
--- @param replace_with string[]
function Function:replace_text(replace_with)
    self.function_range:replace_text(replace_with)
end

--- @param ts_node _99.treesitter.TSNode
---@param cursor _99.Point
---@param context _99.RequestContext
---@return _99.treesitter.Function
function Function.from_ts_node(ts_node, cursor, context)
    local ok, query =
        pcall(vim.treesitter.query.get, context.file_type, function_query)
    local logger = context.logger:set_area("Function")
    if not ok or query == nil then
        logger:fatal("not query or not ok")
        error("failed")
    end

    local func = {}
    for id, node, _ in
        query:iter_captures(ts_node, context.buffer, 0, -1, { all = true })
    do
        local range = Range:from_ts_node(node, context.buffer)
        local name = query.captures[id]
        if range:contains(cursor) then
            if name == "context.function" then
                func.function_node = node
                func.function_range = range
            elseif name == "context.body" then
                func.body_node = node
                func.body_range = range
            end
        end
    end

    --- NOTE: not all functions have bodies... (lua: local function foo() end)
    logger:assert(func.function_node ~= nil, "function_node not found")
    logger:assert(func.function_range ~= nil, "function_range not found")

    return setmetatable(func, Function)
end

--- @param context _99.RequestContext
--- @param cursor _99.Point
--- @return _99.treesitter.Function?
function M.containing_function(context, cursor)
    local buffer = context.buffer
    local lang = context.file_type
    local logger = context and context.logger:set_area("treesitter") or Logger

    logger:error("loading lang", "buffer", buffer, "lang", lang)
    local root = tree_root(buffer, lang)
    if not root then
        logger:debug("LSP: could not find tree root")
        return nil
    end

    local ok, query = pcall(vim.treesitter.query.get, lang, function_query)
    if not ok or query == nil then
        logger:debug(
            "LSP: not ok or query",
            "query",
            vim.inspect(query),
            "lang",
            lang,
            "ok",
            vim.inspect(ok)
        )
        return nil
    end

    --- @type _99.Range
    local found_range = nil
    --- @type _99.treesitter.TSNode
    local found_node = nil
    for id, node, _ in query:iter_captures(root, buffer, 0, -1, { all = true }) do
        local range = Range:from_ts_node(node, buffer)
        local name = query.captures[id]
        if name == "context.function" and range:contains(cursor) then
            if not found_range then
                found_range = range
                found_node = node
            elseif found_range:area() > range:area() then
                found_range = range
                found_node = node
            end
        end
    end

    logger:debug(
        "treesitter#containing_function",
        "found_range",
        found_range and found_range:to_string() or "found_range is nil"
    )

    if not found_range then
        return nil
    end
    logger:assert(
        found_node,
        "INVARIANT: found_range is not nil but found node is"
    )

    ok, query = pcall(vim.treesitter.query.get, lang, function_query)
    if not ok or query == nil then
        logger:fatal("INVARIANT: found_range ", "range", found_range:to_text())
        return
    end

    --- TODO: we need some language specific things here.
    --- that is because comments above the function needs to considered
    return Function.from_ts_node(found_node, cursor, context)
end

--- @param buffer number
--- @return _99.treesitter.Node[]
function M.imports(buffer)
    Logger:assert(false, "not implemented yet", "id", 69420)
    local lang = vim.bo[buffer].ft
    local root = tree_root(buffer, lang)
    if not root then
        Logger:debug("imports: could not find tree root")
        return {}
    end

    local ok, query = pcall(vim.treesitter.query.get, lang, imports_query)

    if not ok or query == nil then
        Logger:debug(
            "imports: not ok or query",
            "query",
            vim.inspect(query),
            "lang",
            lang,
            "ok",
            vim.inspect(ok)
        )
        return {}
    end

    local imports = {}
    for _, match, _ in query:iter_matches(root, buffer, 0, -1, { all = true }) do
        for id, nodes in pairs(match) do
            local name = query.captures[id]
            if name == "import.name" then
                for _, node in ipairs(nodes) do
                    table.insert(imports, node)
                end
            end
        end
    end

    return imports
end

--- Get comments/docstrings immediately preceding a function
--- @param context _99.RequestContext
--- @param func_range _99.Range
--- @return string[]
function M.get_preceding_comments(context, func_range)
    local buffer = context.buffer
    local lang = context.file_type
    local root = tree_root(buffer, lang)
    if not root then
        return {}
    end

    local ok, query = pcall(vim.treesitter.query.get, lang, comments_query)
    if not ok or query == nil then
        return {}
    end

    local comments = {}
    local func_start_row = func_range.start.row

    for id, node, _ in query:iter_captures(root, buffer, 0, -1, { all = true }) do
        local name = query.captures[id]
        if
            name:match("^context%.comment")
            or name:match("^context%.docstring")
        then
            local range = Range:from_ts_node(node, buffer)
            -- Include comments ending within 2 lines before function
            if
                range.end_.row >= func_start_row - 2
                and range.end_.row < func_start_row
            then
                table.insert(comments, range:to_text())
            end
        end
    end

    return comments
end

--- Get enclosing context (class, impl, trait, module, struct, interface)
--- @param context _99.RequestContext
--- @param cursor _99.Point
--- @return table?
function M.get_enclosing_context(context, cursor)
    local buffer = context.buffer
    local lang = context.file_type
    local root = tree_root(buffer, lang)
    if not root then
        return nil
    end

    local ok, query = pcall(vim.treesitter.query.get, lang, context_query)
    if not ok or query == nil then
        return nil
    end

    local enclosing = {}

    for id, node, _ in query:iter_captures(root, buffer, 0, -1, { all = true }) do
        local range = Range:from_ts_node(node, buffer)
        local name = query.captures[id]

        if range:contains(cursor) then
            local kind = name:match("^context%.(%w+)")
            if kind and not enclosing[kind] then
                enclosing[kind] = { node = node, range = range, capture = name }
            elseif kind and enclosing[kind] then
                -- Keep smallest enclosing
                if range:area() < enclosing[kind].range:area() then
                    enclosing[kind] = { node = node, range = range, capture = name }
                end
            end
        end
    end

    return next(enclosing) and enclosing or nil
end

--- For Go: find all interface definitions in the file
--- @param context _99.RequestContext
--- @return table[]
function M.get_go_interfaces(context)
    local buffer = context.buffer
    local root = tree_root(buffer, "go")
    if not root then
        return {}
    end

    local ok, query = pcall(vim.treesitter.query.get, "go", context_query)
    if not ok or query == nil then
        return {}
    end

    local interfaces = {}

    for id, node, _ in query:iter_captures(root, buffer, 0, -1, { all = true }) do
        local name = query.captures[id]
        if name == "context.interface" then
            local range = Range:from_ts_node(node, buffer)
            table.insert(interfaces, {
                range = range,
                text = range:to_text(),
            })
        end
    end

    return interfaces
end

--- For Rust: get impl block header (without full body)
--- @param impl_node _99.treesitter.TSNode
--- @param buffer number
--- @return string
function M.get_rust_impl_header(impl_node, buffer)
    -- Get text up to the opening brace
    local text = vim.treesitter.get_node_text(impl_node, buffer)
    local header = text:match("^(.-){")
    return header and (header .. "{ ... }") or ""
end

--- Helper: search for prototypes in a buffer
--- @param buffer number
--- @param func_name string
--- @return string[]
local function search_prototypes_in_buffer(buffer, func_name)
    local root = tree_root(buffer, "c")
    if not root then
        return {}
    end

    local ok, query = pcall(vim.treesitter.query.get, "c", context_query)
    if not ok or query == nil then
        return {}
    end

    local prototypes = {}
    local proto_nodes = {}

    -- First pass: collect all prototype declarations
    for id, node, _ in query:iter_captures(root, buffer, 0, -1, { all = true }) do
        local name = query.captures[id]
        if name == "context.prototype" then
            table.insert(proto_nodes, node)
        end
    end

    -- Second pass: check names and extract matching prototypes
    for id, node, _ in query:iter_captures(root, buffer, 0, -1, { all = true }) do
        local name = query.captures[id]
        if name == "context.prototype.name" then
            local proto_name = vim.treesitter.get_node_text(node, buffer)
            if proto_name == func_name then
                -- Find the parent declaration node
                local parent = node:parent()
                while parent and parent:type() ~= "declaration" do
                    parent = parent:parent()
                end
                if parent then
                    local range = Range:from_ts_node(parent, buffer)
                    table.insert(prototypes, range:to_text())
                end
            end
        end
    end

    return prototypes
end

--- Helper: search for prototypes in a file path
--- @param file_path string
--- @param func_name string
--- @return string[]
local function search_prototypes_in_file(file_path, func_name)
    -- Read file content
    local file = io.open(file_path, "r")
    if not file then
        return {}
    end
    local content = file:read("*a")
    file:close()

    local lines = vim.split(content, "\n")

    -- Create temporary buffer to parse the header file
    local temp_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("filetype", "c", { buf = temp_buf })

    local protos = search_prototypes_in_buffer(temp_buf, func_name)

    -- Clean up temp buffer
    vim.api.nvim_buf_delete(temp_buf, { force = true })

    return protos
end

--- For C: get local include paths from a file
--- @param context _99.RequestContext
--- @return string[]
function M.get_c_local_includes(context)
    local buffer = context.buffer
    local root = tree_root(buffer, "c")
    if not root then
        return {}
    end

    local ok, query = pcall(vim.treesitter.query.get, "c", includes_query)
    if not ok or query == nil then
        return {}
    end

    local includes = {}

    for id, node, _ in query:iter_captures(root, buffer, 0, -1, { all = true }) do
        local name = query.captures[id]
        if name == "include.local" then
            local path = vim.treesitter.get_node_text(node, buffer)
            -- Remove quotes: "header.h" -> header.h
            path = path:gsub('^"', ""):gsub('"$', "")
            table.insert(includes, path)
        end
    end

    return includes
end

--- For C: find function prototypes in current file and header files
--- @param context _99.RequestContext
--- @param func_name string
--- @return string[]
function M.get_c_prototypes(context, func_name)
    local prototypes = {}
    local seen = {} -- To deduplicate
    local file_dir = vim.fn.fnamemodify(context.full_path, ":h")
    local file_name = vim.fn.fnamemodify(context.full_path, ":t:r") -- filename without extension

    --- Helper to add unique prototypes
    local function add_protos(protos)
        for _, proto in ipairs(protos) do
            if not seen[proto] then
                seen[proto] = true
                table.insert(prototypes, proto)
            end
        end
    end

    -- 1. Search current file
    local current_file_protos =
        search_prototypes_in_buffer(context.buffer, func_name)
    add_protos(current_file_protos)

    -- 2. Check corresponding .h file (same name)
    local header_path = file_dir .. "/" .. file_name .. ".h"
    if vim.fn.filereadable(header_path) == 1 then
        local header_protos = search_prototypes_in_file(header_path, func_name)
        add_protos(header_protos)
    end

    -- 3. Check locally included headers
    local includes = M.get_c_local_includes(context)
    for _, include_path in ipairs(includes) do
        -- Resolve relative to current file's directory
        local full_include_path = file_dir .. "/" .. include_path
        if vim.fn.filereadable(full_include_path) == 1 then
            local include_protos =
                search_prototypes_in_file(full_include_path, func_name)
            add_protos(include_protos)
        end
    end

    return prototypes
end

return M
