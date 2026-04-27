--- @class _99.ops.Opts
--- The options that are used throughout all the interactions with 99.  This
--- includes search, visual, and others
---
--- @docs included
--- @field additional_prompt? string
--- by providing `additional_prompt` you will not be required to provide a prompt.
--- this allows you to define actions based on remaps
---
--- ```lua
--- remap("n", "<leader>9d", function()
---   --- this function could be used to auto debug your project
---   _99.search({
---     additional_prompt = [[
--- run `make test` and debug the test failures and provide me a comprehensive set of steps where
--- the tests are breaking ]]
---   })
--- end)
--- ```
---
--- This would kick off a search job that will run your tests in the background.
--- the resulting failures would be diagnosed and search results would be transfered
--- into a quick fix list.
--- @field additional_rules? _99.Agents.Rule[]
--- can be used to provide extra args.  If you have a skill called "cloudflare" you could
--- provide the rule for cloudflare and its context will be injected into your request

--- @class _99.ops.SearchOpts : _99.ops.Opts
--- See `_99.opts.Opts` for more information.
---
--- There are no properties yet.  But i would like to tweek some behavior based on opts
--- @docs included

--- @class _99.ops.ContinueOpts : _99.ops.Opts
--- Options for continuing a previous 99 request.
---
--- @field last? boolean If true, continue the latest successful request
--- @field type? _99.Prompt.Operation Filter to latest of this type ("vibe", "search", "tutorial", "visual")
--- @docs included

return {
  search = require("99.ops.search"),
  tutorial = require("99.ops.tutorial"),
  over_range = require("99.ops.over-range"),
  vibe = require("99.ops.vibe"),
  continue_chat = require("99.ops.continue"),
}
