local Logger = require("99.logger.logger")
local utils = require("99.utils")
local random_file = utils.random_file
local editor = require("99.editor")

--- @class _99.RequestContext
--- @field md_file_names string[]
--- @field ai_context string[]
--- @field model string
--- @field tmp_file string
--- @field full_path string
--- @field buffer number
--- @field file_type string
--- @field marks table<string, _99.Mark>
--- @field logger _99.Logger
--- @field xid number
--- @field range _99.Range?
--- @field _99 _99.State
local RequestContext = {}
RequestContext.__index = RequestContext

--- @param _99 _99.State
--- @param xid number
--- @return _99.RequestContext
function RequestContext.from_current_buffer(_99, xid)
    local buffer = vim.api.nvim_get_current_buf()
    local full_path = vim.api.nvim_buf_get_name(buffer)
    local file_type = vim.bo[buffer].ft

    local mds = {}
    for _, md in ipairs(_99.md_files) do
        table.insert(mds, md)
    end

    return setmetatable({
        _99 = _99,
        md_file_names = mds,
        ai_context = {},
        tmp_file = random_file(),
        buffer = buffer,
        full_path = full_path,
        file_type = file_type,
        logger = Logger:set_id(xid),
        xid = xid,
        model = _99.model,
        marks = {},
    }, RequestContext)
end

--- @param md_file_name string
--- @return self
function RequestContext:add_md_file_name(md_file_name)
    table.insert(self.md_file_names, md_file_name)
    return self
end

function RequestContext:_read_md_files()
    local cwd = vim.uv.cwd()
    local dir = vim.fn.fnamemodify(self.full_path, ":h")

    while dir:find(cwd, 1, true) == 1 do
        for _, md_file_name in ipairs(self.md_file_names) do
            local md_path = dir .. "/" .. md_file_name
            local file = io.open(md_path, "r")
            if file then
                local content = file:read("*a")
                file:close()
                self.logger:info(
                    "Context#adding md file to the context",
                    "md_path",
                    md_path
                )
                table.insert(self.ai_context, content)
            end
        end

        if dir == cwd then
            break
        end

        dir = vim.fn.fnamemodify(dir, ":h")
    end
end

--- @return string[]
function RequestContext:content()
    return self.ai_context
end

--- @return self
function RequestContext:finalize()
    self:_read_md_files()

    -- Add imports context to help LLM understand dependencies
    local imports_context = self:get_imports_context()
    if imports_context ~= "" then
        table.insert(self.ai_context, imports_context)
    end

    if self.range then
        table.insert(self.ai_context, self._99.prompts.get_file_location(self))
        table.insert(
            self.ai_context,
            self._99.prompts.get_range_text(self.range)
        )
        -- Gather LSP type context if available
        self:_gather_lsp_context()
    end
    table.insert(
        self.ai_context,
        self._99.prompts.tmp_file_location(self.tmp_file)
    )
    return self
end

--- Gathers type information from LSP for the current range.
--- Adds type context to ai_context to help LLM make better decisions.
function RequestContext:_gather_lsp_context()
    if not self.range then
        return
    end

    local lsp = editor.lsp
    if not lsp then
        return
    end

    local logger = self.logger:set_area("RequestContext._gather_lsp_context")

    if not lsp.has_lsp(self.buffer) then
        logger:debug("No LSP available, skipping type context")
        return
    end

    logger:debug("Gathering LSP context for range")
    local type_context = lsp.gather_context_sync(self, 1000)

    if type_context and type_context ~= "" then
        logger:info("Adding LSP type context", "length", #type_context)
        table.insert(self.ai_context, type_context)
    else
        logger:debug("No type context gathered")
    end
end

--- Gathers import information from the current file.
--- Adds import context to ai_context to help LLM understand dependencies.
--- @return string Formatted imports context
function RequestContext:get_imports_context()
    local ts = editor.treesitter
    if not ts then
        return ""
    end

    local imports = ts.imports(self.buffer)
    if #imports == 0 then
        return ""
    end

    local lines = { "<Imports>" }
    for _, imp in ipairs(imports) do
        if imp.alias then
            table.insert(
                lines,
                string.format('  %s = require("%s")', imp.alias, imp.path)
            )
        else
            table.insert(lines, string.format('  require("%s")', imp.path))
        end
    end
    table.insert(lines, "</Imports>")

    return table.concat(lines, "\n")
end

function RequestContext:clear_marks()
    for _, mark in pairs(self.marks) do
        mark:delete()
    end
end

return RequestContext
