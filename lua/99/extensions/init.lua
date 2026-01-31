--- @class _99.Extensions.Source
--- @field init_for_buffer fun(_99: _99.State): nil
--- @field init fun(_99: _99.State): nil
--- @field refresh_state fun(_99: _99.State): nil

--- @type _99.Extensions.Source | nil
local cmp_source = nil

--- @param completion _99.Completion | nil
--- @return _99.Extensions.Source | nil
local function get_source(completion)
  if not completion or completion.source ~= "cmp" then
    return
  end
   local source = completion.source
   if source == "cmp" then
    local cmp = require("99.extensions.cmp")
     return cmp
   end
end

return {
  --- @param _99 _99.State
  init = function(_99)
    local source = get_source(_99.completion)
    if not source then
      return
    end
    source.init(_99)
  end,

  --- @param _99 _99.State
  setup_buffer = function(_99)
    local source = get_source(_99.completion)
    if not source then
      return
    end
    source.init_for_buffer(_99)
  end,

  --- @param _99 _99.State
  refresh = function(_99)
    local source = get_source(_99.completion)
    if not source then
      return
    end
    source.refresh_state(_99)
  end,
}
