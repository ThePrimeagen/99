local Completions = require("99.extensions.completions")
local SOURCE = "99"

--- @class CmpSource
--- @field _99 _99.State
local CmpSource = {}
CmpSource.__index = CmpSource

--- @param _99 _99.State
function CmpSource.new(_99)
  return setmetatable({ _99 = _99 }, CmpSource)
end

function CmpSource.is_available()
  return true
end

function CmpSource.get_debug_name()
  return SOURCE
end

function CmpSource.get_keyword_pattern()
  return Completions.get_keyword_pattern()
end

function CmpSource.get_trigger_characters()
  return Completions.get_trigger_characters()
end

function CmpSource.complete(_, params, callback)
  local before = params.context.cursor_before_line or ""
  local trigger = Completions.detect_trigger(before)

  if not trigger then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local items = Completions.get_completions(trigger)
  callback({ items = items, isIncomplete = false })
end

function CmpSource.resolve(_, completion_item, callback)
  callback(completion_item)
end

function CmpSource.execute(_, completion_item, callback)
  callback(completion_item)
end

--- @type CmpSource | nil
local source = nil

--- @param _ _99.State
local function init_for_buffer(_)
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "99prompt"

  local cmp = require("cmp")
  cmp.setup.buffer({
    sources = { { name = SOURCE } },
    window = {
      completion = { zindex = 1001 },
      documentation = { zindex = 1001 },
    },
  })
end

--- @param _99 _99.State
local function init(_99)
  if source then
    return
  end

  local cmp = require("cmp")
  source = CmpSource.new(_99)
  cmp.register_source(SOURCE, source)
end

--- @param _99 _99.State
local function refresh_state(_99)
  if not source then
    return
  end
  source._99 = _99
end

--- @type _99.Extensions.Source
local source_wrapper = {
  dependency = "cmp",
  init_for_buffer = init_for_buffer,
  init = init,
  refresh_state = refresh_state,
}
return source_wrapper
