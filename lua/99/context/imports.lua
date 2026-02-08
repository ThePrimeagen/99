--- Import context gathering for AI prompts
--- Parses imports using tree-sitter and enriches non-stdlib imports with LSP hover info

local Languages = require("99.language")

local M = {}

--- @class _99.context.Import
--- @field name string The import name (e.g., "pathlib" or "Path")
--- @field module string? The module for "from X import Y" style
--- @field alias string? Alias if import is aliased
--- @field is_stdlib boolean Whether this is a stdlib import
--- @field hover_info string? LSP hover info for non-stdlib imports

--- Extract text from a tree-sitter node
--- @param node _99.treesitter.Node
--- @param buffer number
--- @return string
local function get_node_text(node, buffer)
  local start_row, start_col, end_row, end_col = node:range()
  local lines = vim.api.nvim_buf_get_lines(buffer, start_row, end_row + 1, false)
  if #lines == 0 then
    return ""
  end
  if #lines == 1 then
    return lines[1]:sub(start_col + 1, end_col)
  end
  lines[1] = lines[1]:sub(start_col + 1)
  lines[#lines] = lines[#lines]:sub(1, end_col)
  return table.concat(lines, "\n")
end

--- Parse imports from buffer using tree-sitter query
--- @param buffer number
--- @param file_type string
--- @return _99.context.Import[]
function M.parse_imports(buffer, file_type)
  local imports = {}
  local lang = file_type

  -- Get tree root
  local ok, parser = pcall(vim.treesitter.get_parser, buffer, lang)
  if not ok or not parser then
    return imports
  end

  local tree = parser:parse()[1]
  if not tree then
    return imports
  end
  local root = tree:root()

  -- Get the imports query
  local query_ok, query = pcall(vim.treesitter.query.get, lang, "99-imports")
  if not query_ok or not query then
    return imports
  end

  -- Track current import being built
  local current_import = nil
  local current_decl_id = nil

  for id, node, _ in query:iter_captures(root, buffer, 0, -1, { all = true }) do
    local capture_name = query.captures[id]
    local text = get_node_text(node, buffer)
    local node_id = tostring(node:id())

    -- Get the parent decl node id for grouping
    local parent = node:parent()
    local parent_id = parent and tostring(parent:id()) or node_id

    if capture_name == "import.decl" then
      -- Start a new import declaration
      if current_import and current_import.name then
        -- Check if stdlib
        local check_module = current_import.module or current_import.name
        current_import.is_stdlib = Languages.is_stdlib(file_type, check_module)
        table.insert(imports, current_import)
      end
      current_import = { name = nil, module = nil, alias = nil, is_stdlib = false }
      current_decl_id = node_id
    elseif capture_name == "import.name" then
      if current_import then
        current_import.name = text
      end
    elseif capture_name == "import.module" then
      if current_import then
        current_import.module = text
      end
    elseif capture_name == "import.alias" then
      if current_import then
        current_import.alias = text
      end
    end
  end

  -- Don't forget the last import
  if current_import and current_import.name then
    local check_module = current_import.module or current_import.name
    current_import.is_stdlib = Languages.is_stdlib(file_type, check_module)
    table.insert(imports, current_import)
  end

  return imports
end

--- Format a single import for display
--- @param import _99.context.Import
--- @return string
local function format_import(import)
  local parts = {}

  if import.module then
    -- from X import Y style
    table.insert(parts, import.module .. "." .. import.name)
  else
    -- import X style
    table.insert(parts, import.name)
  end

  if import.alias then
    table.insert(parts, " as " .. import.alias)
  end

  if import.is_stdlib then
    table.insert(parts, " (stdlib)")
  elseif import.hover_info then
    table.insert(parts, ": " .. import.hover_info)
  end

  return table.concat(parts)
end

--- Get LSP hover info for a position
--- @param buffer number
--- @param line number 0-based
--- @param col number 0-based
--- @param cb fun(result: string|nil)
local function get_hover_info(buffer, line, col, cb)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(buffer) },
    position = { line = line, character = col },
  }

  vim.lsp.buf_request(buffer, "textDocument/hover", params, function(err, result, _, _)
    if err or not result or not result.contents then
      cb(nil)
      return
    end

    local content = result.contents
    local text
    if type(content) == "table" then
      if content.value then
        text = content.value
      elseif content.kind then
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
    else
      text = tostring(content)
    end

    -- Clean up markdown fences
    if text then
      text = text:gsub("```%w*\n?", ""):gsub("```", "")
      text = text:gsub("^%s+", ""):gsub("%s+$", "")
      -- Take first line only for brevity
      text = text:match("^([^\n]+)")
    end

    cb(text)
  end)
end

--- Gather import context for AI prompts (async)
--- @param context _99.RequestContext
--- @param cb fun(import_context: string)
function M.gather_import_context(context, cb)
  local buffer = context.buffer
  local file_type = context.file_type

  local imports = M.parse_imports(buffer, file_type)

  if #imports == 0 then
    cb("")
    return
  end

  -- Separate stdlib and non-stdlib
  local stdlib_imports = {}
  local external_imports = {}

  for _, import in ipairs(imports) do
    if import.is_stdlib then
      table.insert(stdlib_imports, import)
    else
      table.insert(external_imports, import)
    end
  end

  -- If no external imports, we're done (no LSP needed)
  if #external_imports == 0 then
    local lines = { "<IMPORTS>" }
    for _, import in ipairs(stdlib_imports) do
      table.insert(lines, format_import(import))
    end
    table.insert(lines, "</IMPORTS>")
    cb(table.concat(lines, "\n"))
    return
  end

  -- For external imports, we could get LSP hover info
  -- For now, just format without hover (can be enhanced later)
  -- TODO: Add async LSP hover resolution for external imports
  local lines = { "<IMPORTS>" }

  for _, import in ipairs(stdlib_imports) do
    table.insert(lines, format_import(import))
  end

  for _, import in ipairs(external_imports) do
    table.insert(lines, format_import(import))
  end

  table.insert(lines, "</IMPORTS>")
  cb(table.concat(lines, "\n"))
end

--- Synchronous version that only includes basic import info
--- @param context _99.RequestContext
--- @return string
function M.gather_import_context_sync(context)
  local buffer = context.buffer
  local file_type = context.file_type

  local imports = M.parse_imports(buffer, file_type)

  if #imports == 0 then
    return ""
  end

  local lines = { "<IMPORTS>" }
  for _, import in ipairs(imports) do
    table.insert(lines, format_import(import))
  end
  table.insert(lines, "</IMPORTS>")

  return table.concat(lines, "\n")
end

return M
