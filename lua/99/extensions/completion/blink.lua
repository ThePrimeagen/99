-- luacheck: no self
local base = require("99.extensions.completion.base")

--- @class BlinkSource
--- @field items _99.Extensions.CompletionItem[] | nil
local BlinkSource = {}
BlinkSource.__index = BlinkSource

function BlinkSource.new()
  local self = setmetatable({}, { __index = BlinkSource })
  return self
end

function BlinkSource:get_keyword_pattern()
  return [[@\k\+]]
end

function BlinkSource:enabled()
  return vim.bo.filetype == "99"
end

function BlinkSource:get_trigger_characters()
  return { "@" }
end

-- pattern was taken from `blink-emoji` to mimic the trigger behavior
local function is_at_mention(line)
  local pattern = [[\%([[:space:]"'`]\|^\)\zs@[[:alnum:]_]*$]]
  return vim.regex(pattern):match_str(line) ~= nil
end

--- @param ctx table blink.cmp context
--- @param callback fun(result: table): nil
function BlinkSource:get_completions(ctx, callback)
  local cursor_before = ctx.line:sub(1, ctx.cursor[2])
  if not is_at_mention(cursor_before) then
    ---@diagnostic disable-next-line: missing-parameter
    return callback()
  end
  local kind = require("blink.cmp.types").CompletionItemKind.File
  local items = base.to_lsp_items(self.items or {}, kind)

  callback({
    items = items,
    is_incomplete_backward = true,
    is_incomplete_forward = false,
  })
end

--- @type BlinkSource | nil
local source = nil

--- @param _99 _99.State
local function init(_99)
  if source then
    source.items = base.build_items(_99)
    return
  end
  source = BlinkSource.new()
  source.items = base.build_items(_99)
end

--- @param _ _99.State
local function init_for_buffer(_) end -- blink is setup globally

--- @param _99 _99.State
local function refresh_state(_99)
  if not source then
    return
  end
  source.items = base.build_items(_99)
end

--- @param _ table | nil
--- @return BlinkSource
local function new(_)
  if source then
    return source
  end
  source = BlinkSource.new()
  return source
end

--- @type _99.Extensions.Source
local source_wrapper = {
  init = init,
  init_for_buffer = init_for_buffer,
  refresh_state = refresh_state,
  new = new,
}
return source_wrapper
