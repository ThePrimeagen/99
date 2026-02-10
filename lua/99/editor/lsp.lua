local Geo = require("99.geo")
local ts = require("99.editor.treesitter")
--- @class Lsp
--- @field config _99.Options Configuration options for the LSP client
local Lsp = {}
Lsp.__index = Lsp

--------------------------------------------------------------------------------
-- TYPE DEFINITIONS
--------------------------------------------------------------------------------
--- @class LspDefinitionResult
--- @field range _99.Range The range in the target document where the definition is located
--- @field uri string The URI of the document containing the definition

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--- @param buffer number The buffer number to make the request for
--- @param position _99.Point The position in the document to get definitions for
--- @param cb fun(res: LspDefinitionResult[] | nil): nil Callback receiving the definition results
local function get_lsp_definitions(buffer, position, cb)
  local line, char = position:to_lsp()
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(buffer),
    position = {
      line = line,
      character = char,
    },
  }

  vim.lsp.buf_request(
    buffer,
    "textDocument/definition",
    params,
    function(_, result, _, _)
      cb(result)
    end
  )
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
    local position = { line = export.line, character = export.col }

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

--- Makes an LSP textDocument/documentSymbol request for a buffer.
---
--- @param bufnr number The buffer number
--- @param cb fun(result: table|nil, err: string|nil): nil Callback with symbol results
local function get_lsp_document_symbols(bufnr, cb)
  local params = { textDocument = { uri = vim.uri_from_bufnr(bufnr) } }

  vim.lsp.buf_request(
    bufnr,
    "textDocument/documentSymbol",
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

--- @class _99.lsp.ExportPosition
--- @field name string
--- @field line number
--- @field col number

--- @class _99.lsp.ExportMember
--- @field name string
--- @field line number
--- @field col number
--- @field kind number|nil

--- @class _99.lsp.ExportMetadata
--- @field kind number|nil
--- @field members _99.lsp.ExportMember[]|nil

--- @alias _99.lsp.ExportMeta table<string, _99.lsp.ExportMetadata>

--- Extracts export keys and metadata from LSP document symbols.
---
--- @param symbols table|nil LSP document symbols
--- @return _99.lsp.ExportPosition[] export_keys
--- @return _99.lsp.ExportMeta export_meta
local function document_symbols_to_exports(symbols)
  local export_keys = {}
  local export_meta = {}

  if not symbols then
    return export_keys, export_meta
  end

  local function add_export(symbol)
    if not symbol or not symbol.name then
      return
    end

    local range = symbol.selectionRange or symbol.range
    if not range or not range.start then
      return
    end

    local name = symbol.name
    table.insert(export_keys, {
      name = name,
      line = range.start.line,
      col = range.start.character,
    })

    export_meta[name] = export_meta[name] or {}
    export_meta[name].kind = symbol.kind

    if symbol.children and #symbol.children > 0 then
      local members = {}
      for _, child in ipairs(symbol.children) do
        local child_range = child.selectionRange or child.range
        if child_range and child_range.start then
          table.insert(members, {
            name = child.name,
            line = child_range.start.line,
            col = child_range.start.character,
            kind = child.kind,
          })
        end
      end
      if #members > 0 then
        export_meta[name].members = members
      end
    end
  end

  local first = symbols[1]
  if first and first.location then
    -- SymbolInformation[]
    for _, symbol in ipairs(symbols) do
      if symbol.location and symbol.location.range then
        table.insert(export_keys, {
          name = symbol.name,
          line = symbol.location.range.start.line,
          col = symbol.location.range.start.character,
        })
        export_meta[symbol.name] = export_meta[symbol.name] or {}
        export_meta[symbol.name].kind = symbol.kind
      end
    end
    return export_keys, export_meta
  end

  -- DocumentSymbol[]
  for _, symbol in ipairs(symbols) do
    add_export(symbol)
  end

  return export_keys, export_meta
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
  local in_index_block = false
  local in_table_block = false

  for line in hover_text:gmatch("[^\n]+") do
    if in_index_block then
      if line:match("^%s*}") then
        in_index_block = false
      end
    elseif in_table_block then
      if line:match("^%s*}") then
        in_table_block = false
      end
    elseif line:match("__index%s*{") then
      in_index_block = true
    elseif not line:match("^```") then
      local cleaned = line
      cleaned = cleaned:gsub("^local%s+", "")
      cleaned = cleaned:gsub("^[%w_]+:%s*", "")
      local table_start = cleaned:match("^(.-)%s*{")
      if table_start then
        cleaned = table_start
        in_table_block = true
      end
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
  clean = clean:gsub("\n.*", "")
  clean = clean:gsub("%s*{.*$", "")

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

--- @param source_bufnr number The buffer number of the source
--- @param position _99.Point The position to resolve
--- @param cb fun(location: { uri: string, res: string, error: string | nil}|nil, err: string|nil): nil
local function resolve_definition_location(source_bufnr, position, cb)
  get_lsp_definitions(source_bufnr, position, function(result)
    if not result or #result == 0 then
      cb(nil, "No definition found at position")
      return
    end

    local item = result[1]
    local uri = item.uri or item.targetUri
    Lsp.get_exports(uri, function(res, err)
      cb({
        uri = uri,
        results = res,
        error = err,
      })
    end)
  end)
end

--- Ensures a target buffer is loaded from a URI.
---
--- @param uri string The target document URI
--- @param cb fun(bufnr: number|nil, filepath: string|nil, err: string|nil): nil
local function with_target_buffer_from_uri(uri, cb)
  local filepath = vim.uri_to_fname(uri)
  ensure_buffer_with_lsp(filepath, function(bufnr, err)
    if err then
      cb(nil, nil, err)
      return
    end
    cb(bufnr, filepath, nil)
  end)
end

local function is_lsp_class_kind(kind)
  return kind == 5 or kind == 11 or kind == 23
end

local function is_lsp_enum_kind(kind)
  return kind == 10
end

local function is_lsp_function_kind(kind)
  return kind == 6 or kind == 9 or kind == 12
end

--------------------------------------------------------------------------------
-- LSP CLASS
--------------------------------------------------------------------------------

--- Creates a new Lsp instance with the given configuration.
---
--- @param config _99.Options The configuration options
--- @return Lsp A new Lsp instance
function Lsp.new(config)
  return setmetatable({
    config = config,
  }, Lsp)
end

--- Stringifies exports for the symbol under a source position using LSP definitions.
---
--- @param source_bufnr number The buffer number containing the reference
--- @param position _99.Point The position of the import path or symbol
--- @param cb fun(result: string, err: string|nil): nil Callback with formatted string or error
function Lsp.stringify_definition_exports(source_bufnr, position, cb)
  resolve_definition_location(source_bufnr, position, function(res)
    cb(res, "")
  end)
  --[[
  resolve_definition_location(source_bufnr, position, function(location, err)
    if err then
      cb("", err)
      return
    end

    local uri = location.uri
    with_target_buffer_from_uri(uri, function(bufnr, filepath, buf_err)
      if buf_err then
        cb("", buf_err)
        return
      end

      local file_lines = vim.fn.readfile(filepath)
      local filetype = vim.bo[bufnr].filetype

      get_lsp_document_symbols(bufnr, function(symbols, sym_err)
        if sym_err then
          cb("", sym_err)
          return
        end

        local export_keys, export_meta = document_symbols_to_exports(symbols)
        if #export_keys == 0 then
          if filetype == "lua" then
            export_keys = find_export_keys(bufnr)
            export_meta = {}
          end
        end

        if #export_keys == 0 then
          cb("", "No exports found")
          return
        end

        get_exports_hover_info(bufnr, export_keys, function(hover_results)
          local classes_to_expand = {}
          for _, export in ipairs(export_keys) do
            local meta = export_meta[export.name] or {}
            local hover = hover_results[export.name] or "unknown"
            local is_class = is_lsp_class_kind(meta.kind)
              or hover:match("__index") ~= nil
              or hover:match(":%s*[%w_]+%s*{") ~= nil

            if is_class then
              local member_positions = meta.members
                or find_class_member_positions(file_lines, export.name)
              if member_positions and #member_positions > 0 then
                table.insert(classes_to_expand, {
                  name = export.name,
                  positions = member_positions,
                })
              end
            end
          end

          if #classes_to_expand == 0 then
            local result = Lsp._format_exports(
              filepath,
              uri,
              export_keys,
              hover_results,
              file_lines,
              {},
              export_meta,
              filetype
            )
            cb(result, nil)
            return
          end

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
                    filepath,
                    uri,
                    export_keys,
                    hover_results,
                    file_lines,
                    all_member_hovers,
                    export_meta,
                    filetype
                  )
                  cb(result, nil)
                end
              end
            )
          end
        end)
      end)
    end)
  end)
    --]]
end

--- Stringifies exports for the symbol under a Treesitter node.
---
--- @param source_bufnr number The buffer number containing the reference
--- @param node _99.treesitter.Node The treesitter node pointing at the import path or symbol
--- @param cb fun(result: string, err: string|nil): nil Callback with formatted string or error
function Lsp.stringify_definition_exports_from_node(source_bufnr, node, cb)
  local position = Geo.Range:from_ts_node(node, source_bufnr).start
  Lsp.stringify_definition_exports(source_bufnr, position, cb)
end

--- Collects export context from a target document URI.
---
--- @param target_uri string The target document URI
--- @param cb fun(context: table|nil, err: string|nil): nil
local function collect_exports_from_uri(target_uri, cb)
  with_target_buffer_from_uri(target_uri, function(bufnr, filepath, buf_err)
    if buf_err then
      cb(nil, buf_err)
      return
    end

    local file_lines = vim.fn.readfile(filepath)
    local filetype = vim.bo[bufnr].filetype

    get_lsp_document_symbols(bufnr, function(symbols, sym_err)
      if sym_err then
        cb(nil, sym_err)
        return
      end

      local export_keys, export_meta = document_symbols_to_exports(symbols)
      if #export_keys == 0 and filetype == "lua" then
        export_keys = find_export_keys(bufnr)
        export_meta = {}
      end

      if #export_keys == 0 then
        cb(nil, "No exports found")
        return
      end

      cb({
        bufnr = bufnr,
        filepath = filepath,
        filetype = filetype,
        file_lines = file_lines,
        export_keys = export_keys,
        export_meta = export_meta,
        uri = target_uri,
      }, nil)
    end)
  end)
end

--- Collects hover info for exports.
---
--- @param context table Export context
--- @param cb fun(hover_results: table<string, string>, err: string|nil): nil
local function collect_export_hovers(context, cb)
  get_exports_hover_info(
    context.bufnr,
    context.export_keys,
    function(hover_results)
      cb(hover_results, nil)
    end
  )
end

--- Collects class member hovers for class exports.
---
--- @param context table Export context
--- @param hover_results table<string, string> Export name -> hover info
--- @param cb fun(class_member_hovers: table<string, table<string, string>>): nil
local function collect_class_member_hovers(context, hover_results, cb)
  local classes_to_expand = {}

  for _, export in ipairs(context.export_keys) do
    local meta = context.export_meta[export.name] or {}
    local hover = hover_results[export.name] or "unknown"
    local is_class = is_lsp_class_kind(meta.kind)
      or hover:match("__index") ~= nil
      or hover:match(":%s*[%w_]+%s*{") ~= nil

    if is_class then
      local member_positions = meta.members
      if not member_positions and context.filetype == "lua" then
        member_positions =
          find_class_member_positions(context.file_lines, export.name)
      end

      if member_positions and #member_positions > 0 then
        table.insert(classes_to_expand, {
          name = export.name,
          positions = member_positions,
        })
      end
    end
  end

  if #classes_to_expand == 0 then
    cb({})
    return
  end

  local pending = #classes_to_expand
  local all_member_hovers = {}

  for _, class_info in ipairs(classes_to_expand) do
    get_class_members_hover(
      context.bufnr,
      class_info.positions,
      function(member_hovers)
        all_member_hovers[class_info.name] = member_hovers
        pending = pending - 1

        if pending == 0 then
          cb(all_member_hovers)
        end
      end
    )
  end
end

--- Builds export definition objects from context and hover data.
---
--- @param context table Export context
--- @param hover_results table<string, string> Export name -> hover info
--- @param class_member_hovers table<string, table<string, string>>
--- @return table[] definitions
local function build_export_definitions(
  context,
  hover_results,
  class_member_hovers
)
  local definitions = {}

  for _, export in ipairs(context.export_keys) do
    local meta = context.export_meta[export.name] or {}
    local def = {
      name = export.name,
      kind = meta.kind,
      hover = hover_results[export.name] or "unknown",
      members = {},
    }

    local member_hovers = class_member_hovers[export.name]
    if member_hovers then
      for member_name, member_hover in pairs(member_hovers) do
        table.insert(def.members, {
          name = member_name,
          hover = member_hover,
        })
      end
    end

    table.insert(definitions, def)
  end

  return definitions
end

--- Stringifies a single export definition.
---
--- @param definition table Definition object
--- @param context table Export context
--- @return string[] lines
local function stringify_export_definition(definition, context)
  local lines = { "" }
  local is_enum = is_lsp_enum_kind(definition.kind)
    or definition.hover:match("enum%s+") ~= nil
  local is_class = is_lsp_class_kind(definition.kind)
    or definition.hover:match("__index") ~= nil
    or definition.hover:match(":%s*[%w_]+%s*{") ~= nil

  if is_enum then
    local values = {}
    if context.filetype == "lua" then
      values = expand_enum_values(context.file_lines, definition.name)
    end
    if #values > 0 then
      table.insert(lines, definition.name .. " = {")
      for _, v in ipairs(values) do
        table.insert(lines, "  " .. v)
      end
      table.insert(lines, "}")
    else
      table.insert(
        lines,
        definition.name .. ": " .. format_hover_output(definition.hover)
      )
    end
    return lines
  end

  if is_class then
    table.insert(lines, definition.name .. " {")
    for _, member in ipairs(definition.members) do
      if member.name ~= "__index" then
        if member.hover:match("function%s") then
          local sig = format_function_signature(member.hover)
          table.insert(lines, "  " .. member.name .. sig)
        else
          local formatted = format_hover_output(member.hover)
          table.insert(lines, "  " .. member.name .. ": " .. formatted)
        end
      end
    end
    table.insert(lines, "}")
    return lines
  end

  if is_lsp_function_kind(definition.kind) then
    local signature = format_function_signature(definition.hover)
    table.insert(lines, definition.name .. signature)
    return lines
  end

  table.insert(
    lines,
    definition.name .. ": " .. format_hover_output(definition.hover)
  )
  return lines
end

--- Gets LSP definitions for all exports in a target document URI.
---
--- @param target_uri string The target document URI
--- @param cb fun(definitions: table[]|nil, context: table|nil, err: string|nil): nil
local function get_lsp_export_definitions(target_uri, cb)
  collect_exports_from_uri(target_uri, function(context, ctx_err)
    if ctx_err then
      cb(nil, nil, ctx_err)
      return
    end

    collect_export_hovers(context, function(hover_results, _)
      collect_class_member_hovers(
        context,
        hover_results,
        function(member_hovers)
          local definitions =
            build_export_definitions(context, hover_results, member_hovers)
          cb(definitions, context, nil)
        end
      )
    end)
  end)
end

--- Stringifies a list of export definitions.
---
--- @param definitions table[] List of export definitions
--- @param context table Export context
--- @return string
local function stringify_export_definitions(definitions, context)
  local out = {}
  table.insert(out, "Module: " .. context.filepath)
  table.insert(out, "URI: " .. context.uri)
  table.insert(out, string.rep("-", 60))

  for _, definition in ipairs(definitions) do
    local lines = stringify_export_definition(definition, context)
    for _, line in ipairs(lines) do
      table.insert(out, line)
    end
  end

  return table.concat(out, "\n")
end

--- Stringifies exports for a target document URI.
---
--- @param target_uri string The target document URI
--- @param cb fun(result: string, err: string|nil): nil Callback with formatted string or error
function Lsp.get_exports(target_uri, cb)
  get_lsp_export_definitions(target_uri, function(definitions, context, err)
    if err then
      cb("", err)
      return
    end

    local result = stringify_export_definitions(definitions, context)
    cb(result, nil)
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
  class_member_hovers,
  export_meta,
  filetype
)
  local out = {}

  table.insert(out, "Module: " .. module_path)
  table.insert(out, "URI: " .. uri)
  table.insert(out, string.rep("-", 60))

  for _, export in ipairs(export_keys) do
    table.insert(out, "")

    local hover = hover_results[export.name] or "unknown"

    local meta = export_meta and export_meta[export.name] or {}
    local is_enum = is_lsp_enum_kind(meta.kind) or hover:match("enum%s+") ~= nil
    local is_class = is_lsp_class_kind(meta.kind)
      or hover:match("__index") ~= nil
      or hover:match(":%s*[%w_]+%s*{") ~= nil

    if is_enum then
      local values = {}
      if filetype == "lua" then
        values = expand_enum_values(file_lines, export.name)
      end
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

      -- Print members with either type or signature
      for method_name, method_hover in pairs(member_hovers) do
        if method_name ~= "__index" then
          if method_hover:match("function%s") then
            local sig = format_function_signature(method_hover)
            table.insert(out, "  " .. method_name .. sig)
          else
            local formatted = format_hover_output(method_hover)
            table.insert(out, "  " .. method_name .. ": " .. formatted)
          end
        end
      end

      table.insert(out, "}")
    else
      if is_lsp_function_kind(meta.kind) then
        local signature = format_function_signature(hover)
        table.insert(out, export.name .. signature)
      else
        local formatted = format_hover_output(hover)
        table.insert(out, export.name .. ": " .. formatted)
      end
    end
  end

  return table.concat(out, "\n")
end

return {
  Lsp = Lsp,
}
