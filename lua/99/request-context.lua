local Logger = require("99.logger.logger")
local utils = require("99.utils")
local random_file = utils.random_file
local geo = require("99.geo")
local Point = geo.Point

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

    if file_type == "typescriptreact" then
        file_type = "typescript"
    end

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

    if self.range then
        local ts = require("99.editor.treesitter")
        local cursor = Point:new(self.range.start.row, self.range.start.col)

        -- 1. Get preceding comments/docstrings
        local comments = ts.get_preceding_comments(self, self.range)
        if #comments > 0 then
            table.insert(
                self.ai_context,
                string.format(
                    "<FunctionDocumentation>\n%s\n</FunctionDocumentation>",
                    table.concat(comments, "\n")
                )
            )
        end

        -- 2. Get enclosing context (class, impl, trait, module, struct, interface)
        local enclosing = ts.get_enclosing_context(self, cursor)
        if enclosing then
            local context_parts = {}

            -- Rust: include impl header only (not full body)
            if self.file_type == "rust" and enclosing.impl then
                local header =
                    ts.get_rust_impl_header(enclosing.impl.node, self.buffer)
                if header and header ~= "" then
                    table.insert(context_parts, "impl block: " .. header)
                end
            end

            -- Other contexts: include full text
            for kind, data in pairs(enclosing) do
                -- Skip impl for Rust (handled above with header only)
                if not (self.file_type == "rust" and kind == "impl") then
                    table.insert(
                        context_parts,
                        string.format("%s:\n%s", kind, data.range:to_text())
                    )
                end
            end

            if #context_parts > 0 then
                table.insert(
                    self.ai_context,
                    string.format(
                        "<EnclosingContext>\n%s\n</EnclosingContext>",
                        table.concat(context_parts, "\n---\n")
                    )
                )
            end
        end

        -- 3. Go: include interface definitions
        if self.file_type == "go" then
            local interfaces = ts.get_go_interfaces(self)
            if #interfaces > 0 then
                local iface_texts = {}
                for _, iface in ipairs(interfaces) do
                    table.insert(iface_texts, iface.text)
                end
                table.insert(
                    self.ai_context,
                    string.format(
                        "<Interfaces>\n%s\n</Interfaces>",
                        table.concat(iface_texts, "\n---\n")
                    )
                )
            end
        end

        -- 4. C: include function prototypes from current file and headers
        if self.file_type == "c" then
            -- Extract function name from range if possible
            local func_text = self.range:to_text()
            local func_name = func_text:match("([%w_]+)%s*%(")
            if func_name then
                local prototypes = ts.get_c_prototypes(self, func_name)
                if #prototypes > 0 then
                    table.insert(
                        self.ai_context,
                        string.format(
                            "<FunctionPrototypes>\n%s\n</FunctionPrototypes>",
                            table.concat(prototypes, "\n")
                        )
                    )
                end
            end
        end

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

function RequestContext:clear_marks()
    for _, mark in pairs(self.marks) do
        mark:delete()
    end
end

return RequestContext
