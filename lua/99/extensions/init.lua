local cmp = require("99.extensions.cmp")

--- @class _99.Extensions.Source
--- @field init_for_buffer fun(_99: _99.State): nil
--- @field init fun(_99: _99.State): nil
--- @field refresh_state fun(_99: _99.State): nil

--- @type table<string, _99.Extensions.Source>
local loaded_sources = {}

--- @param name string | nil
--- @return _99.Extensions.Source | nil
local function get_source(name)
  if not name then
    return nil
  end

  local cached = loaded_sources[name]
  if cached ~= nil then
    return cached or nil
  end

  local ok, source = pcall(require, "99.extensions.completion." .. name)
  if not ok then
    vim.notify(
      string.format("99: completion.source '%s' is not available", name),
      vim.log.levels.ERROR
    )
    ---@diagnostic disable-next-line: assign-type-mismatch
    loaded_sources[name] = false
    return nil
  end

  loaded_sources[name] = source
  return source
end

return {
  --- @param _99 _99.State
  init = function(_99)
    local source_name = _99.completion and _99.completion.source
    if not source_name then
      return
    end

    local source = get_source(source_name)
    if not source then
      _99.completion.source = nil
      return
    end

    local ok, err = pcall(source.init, _99)
    if not ok then
      vim.notify(
        string.format("99: failed to initialize '%s': %s", source_name, err),
        vim.log.levels.ERROR
      )
      _99.completion.source = nil
      return
    end
  end,

  --- @param _99 _99.State
  setup_buffer = function(_99)
    local source = get_source(_99.completion and _99.completion.source)
    if not source then
      return
    end
    source.init_for_buffer(_99)
  end,

  --- @param _99 _99.State
  refresh = function(_99)
    local source = get_source(_99.completion and _99.completion.source)
    if not source then
      return
    end
    source.refresh_state(_99)
  end,
}
