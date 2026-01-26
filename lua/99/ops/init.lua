--- @class _99.ops.Opts
--- @field additional_prompt? string
--- @field additional_rules? _99.Agents.Rule[]
return {
  fill_in_function = require("99.ops.fill-in-function"),
  implement_fn = require("99.ops.implement-fn"),
  over_range = require("99.ops.over-range"),
  refactor = require("99.ops.refactor"),
}
