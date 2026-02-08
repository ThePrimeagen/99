local Logger = require("99.logger.logger")

--- @class _99.LanguageOps
--- @field log_item fun(item_name: string): string
--- @field names table<string, string>
--- @field prompt_context? fun(): string
--- @field is_stdlib? fun(module_name: string): boolean

--- @class _99.Langauges
--- @field languages table<string, _99.LanguageOps>
local M = {
  languages = {},
}

--- @alias _99.langauge.GetLangParam number?

--- @param buf _99.langauge.GetLangParam
--- @return _99.LanguageOps
--- @return string
--- @return number
local function get_langauge(buf)
  local buffer = buf or vim.api.nvim_get_current_buf()
  local file_type = vim.api.nvim_get_option_value("filetype", { buf = buffer })
  local lang = M.languages[file_type]
  if not lang then
    Logger:fatal("language currently not supported", "lang", file_type)
  end
  return lang, file_type, buffer
end

local function validate_function(fn, file_type)
  if type(fn) ~= "function" then
    Logger:fatal("language does not support log_item", "lang", file_type)
  end
end

--- @param _99 _99.State
function M.initialize(_99)
  M.languages = {}
  for _, lang in ipairs(_99.languages) do
    M.languages[lang] = require("99.language." .. lang)
  end
end

--- @param _ _99.State
--- @param item_name string
--- @param buffer number?
--- @return string
function M.log_item(_, item_name, buffer)
  local lang, file_type = get_langauge(buffer)
  validate_function(lang.log_item, file_type)

  return lang.log_item(item_name)
end

--- Get language-specific prompt context
--- @param file_type string
--- @return string
function M.get_prompt_context(file_type)
  local lang = M.languages[file_type]
  if lang and lang.prompt_context then
    return lang.prompt_context()
  end
  return ""
end

--- Check if a module is part of the language's standard library
--- @param file_type string
--- @param module_name string
--- @return boolean
function M.is_stdlib(file_type, module_name)
  local lang = M.languages[file_type]
  if lang and lang.is_stdlib then
    return lang.is_stdlib(module_name)
  end
  return false
end

--[[
-- i wrote this but now i dont know why i did...
-- i must have had a good reason but christmas break made me forget..
--- @param function_node any
---@param body_name string
function M.find_body(function_node, body_name)
    for child in function_node:iter_children() do
        print("test", child:type())
        if child:type() == body_name then
            return child
        else
            M.find_body(child, body_name)
        end
    end
    return nil
end

--- @param function_node _99.treesitter.TSNode
--- @param buffer number
function M.get_body(function_node, buffer)
    local lang, file_type = get_langauge(buffer)
    local body = lang.names.body
    assert(body, "body is not defined in language", "language", file_type)
end
--]]

return M
