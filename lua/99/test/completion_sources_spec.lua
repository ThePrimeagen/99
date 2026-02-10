-- luacheck: globals describe it assert before_each, ignore 121/require
local Agents = require("99.extensions.agents")
local Completions = require("99.extensions.completions")
local eq = assert.are.same

local function clear_cache()
  package.loaded["99"] = nil
  package.loaded["99.extensions.init"] = nil
  package.loaded["99.extensions.completions.cmp"] = nil
  package.loaded["99.extensions.completions.blink"] = nil
  Completions._reset()
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

--- @return _99.State
local function mock_state()
  local _99 = require("99")
  _99.setup({
    completion = {
      source = nil,
      custom_rules = {
        "scratch/custom_rules/",
        "scratch/custom_rules_2/",
      },
    },
  })
  return _99.__get_state()
end

--- Register completion providers from a state (simulates what init() does)
local function register_providers(state)
  Completions._reset()
  Completions.register(Agents.completion_provider(state))
end

describe("completion: setup", function()
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

describe("completion: completions provider", function()
  it("registers and returns trigger characters", function()
    local state = mock_state()
    register_providers(state)

    local triggers = Completions.get_trigger_characters()
    assert(#triggers > 0, "should have triggers")
    assert(
      vim.tbl_contains(triggers, "#"),
      "should contain # trigger for rules"
    )
  end)

  it("returns completions for registered trigger", function()
    local state = mock_state()
    register_providers(state)

    local items = Completions.get_completions("#")
    assert(#items > 0, "should have items for # trigger")
    for _, item in ipairs(items) do
      assert(item.label, "item should have label")
      assert(item.insertText, "item should have insertText")
    end
  end)

  it("returns empty for unregistered trigger", function()
    Completions._reset()
    local items = Completions.get_completions("?")
    eq({}, items)
  end)

  it("handles empty rules", function()
    Completions._reset()
    local empty_state = {
      rules = { custom = {} },
      completion = { custom_rules = {} },
    }
    empty_state.rules = Agents.rules(empty_state)

    Completions.register(Agents.completion_provider(empty_state))
    local items = Completions.get_completions("#")
    eq({}, items)
  end)
end)

describe("completion: blink adapter", function()
  it("loads without error", function()
    local ok, blink = pcall(require, "99.extensions.completions.blink")
    assert(ok, "blink module should load: " .. tostring(blink))
    assert(blink.init, "should have init")
    assert(blink.init_for_buffer, "should have init_for_buffer")
    assert(blink.refresh_state, "should have refresh_state")
    assert(blink.new, "should have new for blink.cmp")
  end)

  it("creates source via new()", function()
    local blink = require("99.extensions.completions.blink")
    mock_state()

    local source = blink.new()
    assert(source, "should create source")
    assert(source.enabled, "source should have enabled method")
    assert(
      source.get_trigger_characters,
      "source should have get_trigger_characters"
    )
    assert(source.get_completions, "source should have get_completions")
  end)

  it("returns trigger characters from providers", function()
    local blink = require("99.extensions.completions.blink")
    local state = mock_state()
    register_providers(state)

    local source = blink.new()
    local triggers = source:get_trigger_characters()
    assert(#triggers > 0, "should have trigger characters")
    assert(
      vim.tbl_contains(triggers, "#"),
      "should contain # trigger for rules"
    )
  end)

  it("calls callback with items for matching trigger", function()
    local blink = require("99.extensions.completions.blink")
    local state = mock_state()
    register_providers(state)

    local source = blink.new()
    local result = nil

    source:get_completions({
      line = "#custom_rule_1",
      cursor = { 1, 16 },
    }, function(r)
      result = r
    end)

    assert(result, "callback should be called")
    assert(result.items, "result should have items")
    assert(type(result.items) == "table", "items should be table")
    eq(false, result.is_incomplete_forward)
    eq(true, result.is_incomplete_backward)
  end)
end)

describe("completion: cmp adapter", function()
  it("loads without error", function()
    local ok, cmp_source = pcall(require, "99.extensions.completions.cmp")
    assert(ok, "cmp module should load: " .. tostring(cmp_source))
    assert(cmp_source.init, "should have init")
    assert(cmp_source.init_for_buffer, "should have init_for_buffer")
    assert(cmp_source.refresh_state, "should have refresh_state")
  end)
end)

describe("completion: registry", function()
  it("loads sources by convention", function()
    local ok_blink = pcall(require, "99.extensions.completions.blink")
    local ok_cmp = pcall(require, "99.extensions.completions.cmp")

    assert(ok_blink, "blink source should be loadable")
    assert(ok_cmp, "cmp source should be loadable")
  end)
end)
