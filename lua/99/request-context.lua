local Logger = require("99.logger.logger")
local utils = require("99.utils")
local random_file = utils.random_file

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
--- @field lsp_context string? LSP gathered context
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
    if self.lsp_context and self.lsp_context ~= "" then
        table.insert(self.ai_context, self.lsp_context)
    end
    if self.range then
        table.insert(self.ai_context, self._99.prompts.get_file_location(self))
        table.insert(
            self.ai_context,
            self._99.prompts.get_range_text(self.range)
        )
    end
    table.insert(
        self.ai_context,
        self._99.prompts.tmp_file_location(self.tmp_file)
    )
    return self
end

--- Gather LSP context asynchronously
--- Call this before finalize() to include LSP symbol information
--- @param callback fun(self: _99.RequestContext) Called when LSP context is gathered (or skipped)
function RequestContext:gather_lsp_context(callback)
    local lsp_config = self._99.lsp_config
    if not lsp_config or not lsp_config.enabled then
        self.logger:debug("LSP context gathering disabled")
        callback(self)
        return
    end

    local lsp = require("99.lsp")
    if not lsp.is_available(self.buffer) then
        self.logger:debug("No LSP client available, skipping LSP context")
        callback(self)
        return
    end

    local lsp_context_builder = require("99.lsp.context")
    lsp_context_builder.build_context_with_timeout(
        self,
        lsp_config.timeout,
        function(result, err)
            if err then
                self.logger:debug("LSP context build failed", "err", err)
            elseif result then
                self.lsp_context = result
                self.logger:info(
                    "LSP context gathered",
                    "length",
                    #result
                )
            end
            callback(self)
        end
    )
end

function RequestContext:clear_marks()
    for _, mark in pairs(self.marks) do
        mark:delete()
    end
end

return RequestContext
