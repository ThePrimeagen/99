-- luacheck: globals describe it assert require
local eq = assert.are.same

--- Clears module cache for fresh state
local function clear_cache()
  package.loaded["99"] = nil
  package.loaded["99.extensions.cmp"] = nil
  package.loaded["99.extensions.init"] = nil
end

--- @param fn function
local function with_cmp_unavailable(fn)
  local original_cmp = package.loaded["cmp"]
  local original_require = require
  package.loaded["cmp"] = nil

  ---@diagnostic disable-next-line: lowercase-global
  require = function(mod)
    if mod == "cmp" then
      error("module 'cmp' not found")
    end
    return original_require(mod)
  end

  local ok, err = pcall(fn)

  ---@diagnostic disable-next-line: lowercase-global
  require = original_require
  package.loaded["cmp"] = original_cmp

  return ok, err
end

describe("extensions", function()
  describe("cmp source", function()
    it("silent when no source configured", function()
      clear_cache()
      local _99 = require("99")

      _99.setup({})

      local state = _99.__get_state()
      eq(nil, state.completion.source)
    end)

    it("silent when source is nil", function()
      clear_cache()
      local _99 = require("99")

      _99.setup({
        completion = {
          source = nil,
          custom_rules = {},
        },
      })

      local state = _99.__get_state()
      eq(nil, state.completion.source)
    end)

    it("disables cmp when source is cmp but cmp not installed", function()
      clear_cache()
      local _99 = require("99")

      with_cmp_unavailable(function()
        _99.setup({
          completion = {
            source = "cmp",
            custom_rules = {},
          },
        })
      end)

      local state = _99.__get_state()
      eq(nil, state.completion.source)
    end)
  end)
end)
