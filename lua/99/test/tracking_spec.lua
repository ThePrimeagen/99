-- luacheck: globals describe it assert
local _99 = require("99")
local Tracking = require("99.state.tracking")
local Prompt = require("99.prompt")
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

  it("finds latest successful request across all modes", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))
    test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

    run(provider, "search", "success", "first search")
    run(provider, "vibe", "failed", "failed vibe")
    run(provider, "tutorial", "success", "latest tutorial")

    local latest = _99.__get_state().tracking:latest_successful()

    assert(latest)
    eq("tutorial", latest.operation)
    eq("latest tutorial", latest.user_prompt)
  end)

  it("finds latest successful request by mode", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))
    test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

    run(provider, "search", "success", "old search")
    run(provider, "vibe", "success", "new vibe")

    local latest_search = _99.__get_state().tracking:latest_successful("search")

    assert(latest_search)
    eq("search", latest_search.operation)
    eq("old search", latest_search.user_prompt)
  end)

  it("returns nil when no matching successful request exists", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))
    test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

    run(provider, "search", "failed", "failed search")

    eq(nil, _99.__get_state().tracking:latest_successful("search"))
  end)

  it("completed() does not count ready requests", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))
    test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

    local state = _99.__get_state()
    local prompt = Prompt.search(state)
    state.tracking:track(prompt)

    eq(0, state.tracking:completed())
    eq("ready", prompt.state)
  end)

  it(
    "setup can set a count to 0 explicitly and serialization respects it",
    function()
      local previous_counts = vim.deepcopy(Tracking.__config.serialize_count)
      Tracking.setup({
        serialize_counts = {
          vibe = 0,
          search = 1,
          tutorial = 1,
          visual = 0,
        },
      })

      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))
      test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

      run(provider, "vibe", "success", "vibe request")
      run(provider, "search", "success", "search request")

      local serialized = _99.__get_state().tracking:serialize()
      local vibe_count = 0
      local search_count = 0

      for _, request in ipairs(serialized.requests) do
        if request.data.type == "vibe" then
          vibe_count = vibe_count + 1
        elseif request.data.type == "search" then
          search_count = search_count + 1
        end
      end

      eq(0, vibe_count)
      eq(1, search_count)

      Tracking.__config.serialize_count = previous_counts
    end
  )

  it("serializes sessions by request count instead of turn count", function()
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

    _99.vibe({ additional_prompt = "first vibe" })
    provider:resolve("success", "first response")
    test_utils.next_frame()
    _99.continue({
      type = "vibe",
      last = true,
      additional_prompt = "second vibe",
    })
    provider:resolve("success", "second response")
    test_utils.next_frame()

    local serialized = _99.__get_state().tracking:serialize()
    local vibe_count = 0
    local vibe_request = nil

    for _, request in ipairs(serialized.requests) do
      if request.data.type == "vibe" then
        vibe_count = vibe_count + 1
        vibe_request = request
      end
    end

    eq(1, vibe_count)
    assert(vibe_request)
    eq(2, #vibe_request.turns)
    eq("second vibe", vibe_request.turns[2].user_prompt)

    Tracking.__config.serialize_count = previous_counts
  end)

  it(
    "latest_successful returns most recently completed, not most recently started",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))

      local state = _99.__get_state()

      local prompt_a = Prompt.search(state)
      prompt_a.user_prompt = "request A"
      prompt_a.state = "success"
      prompt_a.started_at = 100
      prompt_a.completed_at = 300
      prompt_a:append_turn("request A", "result A")
      state.tracking:track(prompt_a)

      local prompt_b = Prompt.search(state)
      prompt_b.user_prompt = "request B"
      prompt_b.state = "success"
      prompt_b.started_at = 200
      prompt_b.completed_at = 250
      prompt_b:append_turn("request B", "result B")
      state.tracking:track(prompt_b)

      local latest = state.tracking:latest_successful()

      -- Should return A because it completed later, even though B started later
      assert(latest)
      eq("request A", latest.user_prompt)
    end
  )

  it(
    "latest_successful by type returns most recently completed for that type",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))

      local state = _99.__get_state()

      local prompt_a = Prompt.vibe(state)
      prompt_a.user_prompt = "vibe A"
      prompt_a.state = "success"
      prompt_a.started_at = 100
      prompt_a.completed_at = 300
      prompt_a:append_turn("vibe A", "result A")
      state.tracking:track(prompt_a)

      local prompt_b = Prompt.vibe(state)
      prompt_b.user_prompt = "vibe B"
      prompt_b.state = "success"
      prompt_b.started_at = 200
      prompt_b.completed_at = 250
      prompt_b:append_turn("vibe B", "result B")
      state.tracking:track(prompt_b)

      local prompt_c = Prompt.search(state)
      prompt_c.user_prompt = "search C"
      prompt_c.state = "success"
      prompt_c.started_at = 150
      prompt_c.completed_at = 400
      prompt_c:append_turn("search C", "result C")
      state.tracking:track(prompt_c)

      local latest_vibe = state.tracking:latest_successful("vibe")

      -- Should return A because it completed later
      assert(latest_vibe)
      eq("vibe A", latest_vibe.user_prompt)
    end
  )

  it(
    "serialize and reload preserves latest_successful by completion time",
    function()
      local previous_counts = vim.deepcopy(Tracking.__config.serialize_count)
      Tracking.setup({
        serialize_counts = {
          vibe = 2,
          search = 0,
          tutorial = 0,
          visual = 0,
        },
      })

      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))

      local state = _99.__get_state()

      local prompt_a = Prompt.vibe(state)
      prompt_a.user_prompt = "vibe A"
      prompt_a.state = "success"
      prompt_a.started_at = 100
      prompt_a.completed_at = 200
      prompt_a:append_turn("vibe A", "result A")
      state.tracking:track(prompt_a)

      local prompt_b = Prompt.vibe(state)
      prompt_b.user_prompt = "vibe B"
      prompt_b.state = "success"
      prompt_b.started_at = 150
      prompt_b.completed_at = 300
      prompt_b:append_turn("vibe B", "result B")
      state.tracking:track(prompt_b)

      local serialized = state.tracking:serialize()

      -- Create new tracking from serialized data
      local new_tracking = Tracking.new(state, serialized)

      -- Should return B because it completed later
      local latest = new_tracking:latest_successful("vibe")
      assert(latest)
      eq("vibe B", latest.user_prompt)

      Tracking.__config.serialize_count = previous_counts
    end
  )
end)
