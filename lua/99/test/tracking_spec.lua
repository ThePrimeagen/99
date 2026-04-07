-- luacheck: globals describe it assert
local _99 = require("99")
local Tracking = require("99.state.tracking")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

local function run(provider, operation, status, prompt)
  _99[operation]({ additional_prompt = prompt })
  provider:resolve(status, "result")
end

describe("tracking", function()
  it("serializes requests based on configured counts", function()
    local previous_counts = vim.deepcopy(Tracking.__config.serialize_count)
    Tracking.setup({
      serialize_counts = {
        vibe = 1,
        search = 1,
        tutorial = 3,
        visual = 0,
      },
    })

    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))
    test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

    run(provider, "search", "success", "search one")
    run(provider, "search", "success", "search two")
    run(provider, "vibe", "success", "vibe one")
    run(provider, "vibe", "success", "vibe two")
    run(provider, "tutorial", "success", "tutorial one")
    run(provider, "tutorial", "success", "tutorial two")
    run(provider, "tutorial", "success", "tutorial three")
    run(provider, "tutorial", "success", "tutorial four")
    run(provider, "search", "failed", "search failed")

    local serialized = _99.__get_state().tracking:serialize()
    local actual_counts = {
      search = 0,
      vibe = 0,
      tutorial = 0,
      visual = 0,
    }

    for _, request in ipairs(serialized.requests) do
      actual_counts[request.data.type] = actual_counts[request.data.type] + 1
    end

    eq(1, actual_counts.search)
    eq(1, actual_counts.vibe)
    eq(3, actual_counts.tutorial)
    eq(0, actual_counts.visual)
    eq(5, #serialized.requests)

    Tracking.__config.serialize_count = previous_counts
  end)

  it("successful returns things in reverse order", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))
    test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

    run(provider, "search", "success", "first success")
    run(provider, "search", "failed", "failed request")
    run(provider, "vibe", "success", "second success")
    run(provider, "tutorial", "success", "third success")

    local successful = _99.__get_state().tracking:successful()
    eq(3, #successful)
    eq("third success", successful[1].user_prompt)
    eq("second success", successful[2].user_prompt)
    eq("first success", successful[3].user_prompt)
  end)
end)
