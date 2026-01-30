local helpers = require("99.extensions.agents.helpers")
local Logger = require("99.logger.logger")
local M = {}

--- @class _99.Agents.Rule
--- @field name string
--- @field path string

--- @class _99.Agents.Rules
--- @field custom _99.Agents.Rule[]
--- @field by_name table<string, _99.Agents.Rule[]>

--- @class _99.Agents.Agent
--- @field rules _99.Agents.Rules

--- @param map table<string, _99.Agents.Rule[]>
--- @param rules _99.Agents.Rule[]
local function add_rule_by_name(map, rules)
  for _, r in ipairs(rules) do
    if map[r.name] == nil then
      map[r.name] = {}
    end
    table.insert(map[r.name], r)
  end
end

---@param _99 _99.State
---@return _99.Agents.Rules
function M.rules(_99)
  local custom = {}
  for _, path in ipairs(_99.completion.custom_rules or {}) do
    local custom_rules = helpers.ls(path)
    for _, r in ipairs(custom_rules) do
      table.insert(custom, r)
    end
  end

  local by_name = {}
  add_rule_by_name(by_name, custom)
  return {
    by_name = by_name,
    custom = custom,
  }
end

--- @param rules _99.Agents.Rules
--- @return _99.Agents.Rule[]
function M.rules_to_items(rules)
  local items = {}
  for _, rule in ipairs(rules.custom or {}) do
    table.insert(items, rule)
  end
  return items
end

--- @param rules _99.Agents.Rules
---@param path string
---@return _99.Agents.Rule | nil
function M.get_rule_by_path(rules, path)
  for _, rule in ipairs(rules.custom or {}) do
    if rule.path == path then
      return rule
    end
  end
  return nil
end

--- @param rules _99.Agents.Rules
---@param token string
---@return boolean
function M.is_rule(rules, token)
  for _, rule in ipairs(rules.custom or {}) do
    if rule.path == token then
      return true
    end
  end
  return false
end

--- @param rules _99.Agents.Rules
--- @param haystack string
--- @return _99.Agents.Rule[]
function M.find_rules(rules, haystack)
  --- @type _99.Agents.Rule[]
  local out = {}

  for word in haystack:gmatch("@%S+") do
    local rule_string = word:sub(2)
    local rule = M.get_rule_by_path(rules, rule_string)
    if rule then
      table.insert(out, rule)
    end
  end

  return out
end

---@param rules _99.Agents.Rules
---@param prompt string
---@return {names: string[], rules: _99.Agents.Rules[]}
function M.by_name(rules, prompt)
  --- @type table<string, boolean>
  local found = {}

  --- @type string[]
  local names = {}

  --- @type _99.Agents.Rule[]
  local out_rules = {}
  for word in prompt:gmatch("%S+") do
    if word:sub(1, 1) == "@" then
      local w = word:sub(2)
      local rules_by_name = rules.by_name[w]
      if rules_by_name and found[w] == nil then
        for _, r in ipairs(rules_by_name) do
          table.insert(out_rules, r)
        end
        table.insert(names, w)
        found[w] = true
      end
    end
  end

  return {
    names = names,
    rules = out_rules,
  }
end

return M
