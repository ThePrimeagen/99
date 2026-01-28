--------------------------------------------------------------------------------
-- TYPE DEFINITIONS
--------------------------------------------------------------------------------

--- @class LspPosition
--- @field character number Zero-based character offset within a line
--- @field line number Zero-based line number

--- @class LspRange
--- @field start LspPosition The start position of the range (inclusive)
--- @field end LspPosition The end position of the range (exclusive)

--- @class LspDefinitionResult
--- @field range LspRange The range in the target document where the definition is located
--- @field uri string The URI of the document containing the definition

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--- Converts a Treesitter node's position to an LSP-compatible position.
---
--- @param node _99.treesitter.Node The treesitter node to convert
--- @return LspPosition The LSP-compatible position (0-based line and character)
local function ts_node_to_lsp_position(node)
  local start_row, start_col, _, _ = node:range()
  return { line = start_row, character = start_col }
end

--- Makes an LSP textDocument/definition request for a given position.
---
--- @param buffer number The buffer number to make the request for
--- @param position LspPosition The position in the document to get definitions for
--- @param cb fun(res: LspDefinitionResult[] | nil): nil Callback receiving the definition results
local function get_lsp_definitions(buffer, position, cb)
  local params = vim.lsp.util.make_position_params()
  params.position = position

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
---
--- @param require_path string The Lua require path (e.g., "99.logger.logger")
--- @return string|nil The absolute file path, or nil if it can't be resolved
local function resolve_require_path(require_path)
  local relative_path = "lua/" .. require_path:gsub("%.", "/") .. ".lua"
  local results = vim.api.nvim_get_runtime_file(relative_path, false)

  if results and #results > 0 then
    return results[1]
  end

  -- Also try init.lua for module directories
  local init_path = "lua/" .. require_path:gsub("%.", "/") .. "/init.lua"
  results = vim.api.nvim_get_runtime_file(init_path, false)

  if results and #results > 0 then
    return results[1]
  end

  return nil
end

--- Ensures a buffer is loaded and has LSP attached, then calls the callback.
---
--- @param filepath string The file path to load
--- @param cb fun(bufnr: number|nil, err: string|nil): nil Callback with buffer number or error
local function ensure_buffer_with_lsp(filepath, cb)
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(filepath)
  end

  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  vim.schedule(function()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    if #clients == 0 then
      cb(nil, "No LSP client attached to buffer for: " .. filepath)
      return
    end
    cb(bufnr, nil)
  end)
end

--- Makes an LSP textDocument/hover request for a given position.
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
---
--- @param bufnr number The buffer number
--- @return { name: string, line: number, col: number }[] List of exported names with positions
local function find_export_keys(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local exports = {}

  -- Find the last return statement
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

  -- Check if it's a simple `return M` style
  local simple_return =
    lines[return_line_idx]:match("^%s*return%s+([%w_]+)%s*$")
  if simple_return then
    local col = lines[return_line_idx]:find(simple_return)
    table.insert(exports, {
      name = simple_return,
      line = return_line_idx - 1,
      col = col - 1,
    })
    return exports
  end

  -- Parse `return { Key = Value, ... }` style
  for i = return_line_idx, #lines do
    local line = lines[i]
    for key, col_start in line:gmatch("()([%w_]+)%s*=") do
      key, col_start = col_start, key
      if key ~= "" and not key:match("^%d") then
        table.insert(exports, {
          name = key,
          line = i - 1,
          col = col_start - 1,
        })
      end
    end
  end

  return exports
end

--- Gets the hover information for each exported symbol using LSP.
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
    local line_text =
      vim.api.nvim_buf_get_lines(bufnr, export.line, export.line + 1, false)[1]

    local pattern = export.name .. "%s*=%s*()"
    local value_start = line_text:match(pattern)
    local hover_col = value_start and (value_start - 1) or export.col
    local position = { line = export.line, character = hover_col }

    get_lsp_hover(bufnr, position, function(result, _)
      if result and result.contents then
        local content = result.contents
        if type(content) == "table" then
          if content.value then
            results[export.name] = content.value
          elseif content.kind == "markdown" then
            results[export.name] = content.value
          else
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

--- Finds all method/field definitions for a class in the source file.
---
--- @param file_lines string[] The file contents
--- @param class_name string The name of the class (e.g., "Lsp")
--- @return { name: string, line: number, col: number }[] List of member positions
local function find_class_member_positions(file_lines, class_name)
  local members = {}

  for i, line in ipairs(file_lines) do
    local method_name =
      line:match("^%s*function%s+" .. class_name .. "[%.:]([%w_]+)%s*%(")
    if method_name then
      local col = line:find(method_name, 1, true)
      table.insert(members, {
        name = method_name,
        line = i - 1,
        col = col and (col - 1) or 0,
      })
    end

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

--- Removes markdown fencing and cleans hover output.
---
--- @param hover_text string The raw hover text from LSP
--- @return string The cleaned type information
local function format_hover_output(hover_text)
  if not hover_text or hover_text == "unknown" then
    return "unknown"
  end

  local lines = {}

  for line in hover_text:gmatch("[^\n]+") do
    if not line:match("^```") then
      local cleaned = line
      cleaned = cleaned:gsub("^local%s+", "")
      cleaned = cleaned:gsub("^[%w_]+:%s*", "")
      if cleaned ~= "" then
        table.insert(lines, cleaned)
      end
    end
  end

  return table.concat(lines, "\n")
end

--- Formats a function hover result into TypeScript-style signature.
---
--- @param hover_text string The hover text from LSP
--- @return string The formatted signature like "(a: number, b: string): boolean"
local function format_function_signature(hover_text)
  local clean = hover_text:gsub("```%w*\n?", ""):gsub("```", "")
  clean = clean:gsub("^%s*", ""):gsub("%s*$", "")

  local params, ret =
    clean:match("function%s*[%w_%.%:]*%((.-)%)%s*:%s*([^\n]+)")
  if params then
    return string.format("(%s): %s", params, ret or "nil")
  else
    params = clean:match("function%s*[%w_%.%:]*%((.-)%)")
    if params then
      return string.format("(%s): nil", params)
    end
  end

  return clean
end

--- Extracts all enum values from source (not truncated like hover).
---
--- @param file_lines string[] The file contents
--- @param symbol_name string The name of the enum symbol
--- @return string[] Array of enum entries like "Key = value"
local function expand_enum_values(file_lines, symbol_name)
  local values = {}

  for i, line in ipairs(file_lines) do
    if
      line:match("local%s+" .. symbol_name .. "%s*=")
      or line:match(symbol_name .. "%s*=%s*{")
    then
      local j = i
      while j <= #file_lines do
        local enum_line = file_lines[j]

        if enum_line:match("^%s*}") then
          break
        end

        local key, value = enum_line:match("^%s*([%w_]+)%s*=%s*([^,]+)")
        if key and value then
          value = value:match("^%s*(.-)%s*,?%s*$")
          table.insert(values, key .. " = " .. value)
        end

        j = j + 1
      end
      break
    end
  end

  return values
end

--------------------------------------------------------------------------------
-- LSP CLASS
--------------------------------------------------------------------------------

--- @class Lsp
--- @field config _99.Options Configuration options for the LSP client
local Lsp = {}
Lsp.__index = Lsp

--- Creates a new Lsp instance with the given configuration.
---
--- @param config _99.Options The configuration options
--- @return Lsp A new Lsp instance
function Lsp.new(config)
  return setmetatable({
    config = config,
  }, Lsp)
end

--------------------------------------------------------------------------------
-- MODULE EXPORT STRINGIFICATION
--------------------------------------------------------------------------------

--- Converts module exports to a formatted string representation.
--- This is the main entry point for getting a stringified view of a module's exports.
---
--- @param require_path string The Lua require path (e.g., "99", "99.logger.logger")
--- @param cb fun(result: string, err: string|nil): nil Callback with formatted string or error
function Lsp.stringify_module_exports(require_path, cb)
  local resolved_path = resolve_require_path(require_path)

  if not resolved_path then
    cb(
      "",
      "Could not resolve module path: "
        .. require_path
        .. ". The module may not be in runtimepath."
    )
    return
  end

  local uri = vim.uri_from_fname(resolved_path)

  ensure_buffer_with_lsp(resolved_path, function(bufnr, err)
    if err then
      cb("", err)
      return
    end

    local export_keys = find_export_keys(bufnr)

    if #export_keys == 0 then
      cb("", "No exports found in return statement")
      return
    end

    get_exports_hover_info(bufnr, export_keys, function(hover_results)
      local file_lines = vim.fn.readfile(resolved_path)

      -- Collect classes that need member expansion
      local classes_to_expand = {}
      for _, export in ipairs(export_keys) do
        local hover = hover_results[export.name] or "unknown"
        local is_class = hover:match("__index") ~= nil
          or hover:match(":%s*[%w_]+%s*{") ~= nil

        if is_class then
          local member_positions =
            find_class_member_positions(file_lines, export.name)
          if #member_positions > 0 then
            table.insert(classes_to_expand, {
              name = export.name,
              positions = member_positions,
            })
          end
        end
      end

      -- If no classes, format immediately
      if #classes_to_expand == 0 then
        local result = Lsp._format_exports(
          require_path,
          uri,
          export_keys,
          hover_results,
          file_lines,
          {}
        )
        cb(result, nil)
        return
      end

      -- Get hover for class members
      local pending = #classes_to_expand
      local all_member_hovers = {}

      for _, class_info in ipairs(classes_to_expand) do
        get_class_members_hover(
          bufnr,
          class_info.positions,
          function(member_hovers)
            all_member_hovers[class_info.name] = member_hovers
            pending = pending - 1

            if pending == 0 then
              local result = Lsp._format_exports(
                require_path,
                uri,
                export_keys,
                hover_results,
                file_lines,
                all_member_hovers
              )
              cb(result, nil)
            end
          end
        )
      end
    end)
  end)
end

--- Internal function to format exports into a string.
---
--- @param module_path string The module require path
--- @param uri string The file URI
--- @param export_keys { name: string, line: number, col: number }[] Export positions
--- @param hover_results table<string, string> Export name -> hover info
--- @param file_lines string[] The source file lines
--- @param class_member_hovers table<string, table<string, string>> Class name -> member hovers
--- @return string The formatted export string
function Lsp._format_exports(
  module_path,
  uri,
  export_keys,
  hover_results,
  file_lines,
  class_member_hovers
)
  local out = {}

  table.insert(out, "Module: " .. module_path)
  table.insert(out, "URI: " .. uri)
  table.insert(out, string.rep("-", 60))

  for _, export in ipairs(export_keys) do
    table.insert(out, "")

    local hover = hover_results[export.name] or "unknown"

    local is_enum = hover:match("enum%s+") ~= nil
    local is_class = hover:match("__index") ~= nil
      or hover:match(":%s*[%w_]+%s*{") ~= nil

    if is_enum then
      local values = expand_enum_values(file_lines, export.name)
      if #values > 0 then
        table.insert(out, export.name .. " = {")
        for _, v in ipairs(values) do
          table.insert(out, "  " .. v)
        end
        table.insert(out, "}")
      else
        table.insert(out, export.name .. ": " .. format_hover_output(hover))
      end
    elseif is_class then
      local member_hovers = class_member_hovers[export.name] or {}
      table.insert(out, export.name .. " {")

      -- Extract fields from class hover
      local class_fields = {}
      for line in hover:gmatch("[^\n]+") do
        local field_name, field_type = line:match("^%s*([%w_]+):%s*([^,}]+)")
        if field_name and field_type then
          field_type = field_type:match("^%s*(.-)%s*,?$")
          if field_type ~= "function" then
            class_fields[field_name] = field_type
          end
        end
      end

      -- Print fields
      for field_name, field_type in pairs(class_fields) do
        if field_name ~= "__index" then
          table.insert(out, "  " .. field_name .. ": " .. field_type)
        end
      end

      -- Print methods with full signatures
      for method_name, method_hover in pairs(member_hovers) do
        if method_name ~= "__index" then
          local sig = format_function_signature(method_hover)
          table.insert(out, "  " .. method_name .. sig)
        end
      end

      table.insert(out, "}")
    else
      local formatted = format_hover_output(hover)
      table.insert(out, export.name .. ": " .. formatted)
    end
  end

  return table.concat(out, "\n")
end

--- Get all references to symbol at cursor position
--- @param bufnr number
--- @param cb fun(refs: {uri: string, range: LspRange}[])
function Lsp.get_references(bufnr, cb)
  local win = vim.api.nvim_get_current_win()
  local params = vim.lsp.util.make_position_params(win)
  params.context = { includeDeclaration = true }

  vim.lsp.buf_request(
    bufnr,
    "textDocument/references",
    params,
    function(err, result)
      if err or not result then
        cb({})
        return
      end
      cb(result)
    end
  )
end

return {
  Lsp = Lsp,
}
