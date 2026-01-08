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

    local root = tree_root(buffer, lang)
    if not root then
        logger:debug(
            "TreeSitter: could not find tree root - is treesitter parser installed?",
            "lang",
            lang
        )
        return nil
    end

    local ok, query = pcall(vim.treesitter.query.get, lang, function_query)
    if not ok or query == nil then
        logger:debug(
            "treesitter: query not found - does queries/"
                .. lang
                .. "/99-function.scm exist?",
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
        found_range and found_range:to_string() or "nil",
        "lang",
        lang,
        "cursor",
        cursor.row .. ":" .. cursor.col
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

return M
