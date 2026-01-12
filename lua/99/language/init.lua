local Logger = require("99.logger.logger")
local config = require("99.language.config")

--- @class _99.LanguageOps
--- @field log_item fun(item_name: string): string
--- @field names table<string, string>

--- @class _99.Langauges
--- @field languages table<string, _99.LanguageOps>
local M = {
    languages = {},
}

--- @alias _99.langauge.GetLangParam _99.Location | number?

--- @param bufferOrLoc _99.langauge.GetLangParam
--- @return _99.LanguageOps
--- @return string
--- @return number
local function get_langauge(bufferOrLoc)
    if type(bufferOrLoc) == "number" or not bufferOrLoc then
        local buffer = bufferOrLoc or vim.api.nvim_get_current_buf()
        local file_type =
            vim.api.nvim_get_option_value("filetype", { buf = buffer })
        local lang = M.languages[file_type]
        if not lang then
            Logger:fatal("language currently not supported", "lang", file_type)
        end
        return lang, file_type, buffer
    end

    local file_type = bufferOrLoc.file_type
    local lang = M.languages[file_type]
    if not lang then
        Logger:fatal("language currently not supported", "lang", file_type)
    end
    return lang, file_type, bufferOrLoc.buffer
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
        M.languages[lang] = config.get(lang)
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
