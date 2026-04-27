-- luacheck: globals describe it assert
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local continue_module = require("99.ops.continue")
local Prompt = require("99.prompt")
local Window = require("99.window")
local eq = assert.are.same

describe("continue operation", function()
  after_each(function()
    test_utils.clean_files()
    -- Ensure we exit visual mode after each test
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
      "n",
      false
    )
  end)

  --- Helper to create a source prompt with turns for testing
  --- @param operation "vibe" | "search" | "tutorial" | "visual"
  --- @param turns table[] Array of {user_prompt, response} tables
  --- @return _99.Prompt
  local function create_source_with_turns(operation, turns)
    local state = _99.__get_state()
    local source

    if operation == "vibe" then
      source = Prompt.vibe(state)
    elseif operation == "search" then
      source = Prompt.search(state)
    elseif operation == "tutorial" then
      source = Prompt.tutorial(state)
    elseif operation == "visual" then
      -- For visual, we need a buffer with content and selection
      local buffer = test_utils.create_file({ "local value = 1" }, "lua", 1, 0)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd("normal! v$")
      source = Prompt.visual(state)
      -- Exit visual mode after creating the prompt
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
        "n",
        false
      )
    else
      error("unknown operation: " .. tostring(operation))
    end

    source.state = "success"
    source.user_prompt = turns[1] and turns[1].user_prompt or "test prompt"

    -- Add turns
    for _, turn in ipairs(turns) do
      source:append_turn(turn.user_prompt, turn.response)
    end

    return source
  end

  it(
    "continues latest vibe source by dispatching vibe op with stitched prompt",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))

      -- Create a source vibe prompt with turns
      local source = create_source_with_turns("vibe", {
        { user_prompt = "make this clearer", response = "first vibe response" },
      })

      local ops = require("99.ops")
      local state = _99.__get_state()

      -- Call continue.run directly
      local xid = continue_module.run(state, ops, source, {
        additional_prompt = "less abstraction",
      })

      -- Verify a request was made
      assert(xid, "expected xid to be returned")
      assert(provider.request, "expected provider.request to be set")

      -- Verify the operation is vibe
      eq("vibe", provider.request.prompt.operation)

      -- Verify the stitched prompt contains the conversation history
      local query = provider.request.query
      assert.matches("continuing a previous 99.vibe request", query, 1, true)
      assert.matches("make this clearer", query, 1, true)
      assert.matches("first vibe response", query, 1, true)
      assert.matches("less abstraction", query, 1, true)
    end
  )

  it("continues latest search source with search op", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    -- Create a source search prompt with turns
    local source = create_source_with_turns("search", {
      {
        user_prompt = "find parser",
        response = "src/parser.lua:1: parser found",
      },
    })

    local ops = require("99.ops")
    local state = _99.__get_state()

    -- Call continue.run directly
    local xid = continue_module.run(state, ops, source, {
      additional_prompt = "narrow to tests",
    })

    -- Verify a request was made
    assert(xid, "expected xid to be returned")
    assert(provider.request, "expected provider.request to be set")

    -- Verify the operation is search
    eq("search", provider.request.prompt.operation)

    -- Verify the stitched prompt contains the conversation history
    local query = provider.request.query
    assert.matches("continuing a previous 99.search request", query, 1, true)
    assert.matches("find parser", query, 1, true)
    assert.matches("src/parser.lua:1: parser found", query, 1, true)
    assert.matches("narrow to tests", query, 1, true)
  end)

  it(
    "returns nil and does not start provider when source has no turns",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))

      -- Create a source vibe prompt WITHOUT turns
      local source = Prompt.vibe(_99.__get_state())
      source.state = "success"
      source.user_prompt = "test prompt"
      -- Intentionally NOT adding any turns

      local ops = require("99.ops")
      local state = _99.__get_state()

      -- Call continue.run directly
      local xid = continue_module.run(state, ops, source, {
        additional_prompt = "try again",
      })

      -- Verify no request was made
      eq(nil, xid)
      eq(nil, provider.request)
    end
  )

  it("returns nil when additional_prompt is not provided", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    -- Create a source with turns
    local source = create_source_with_turns("vibe", {
      { user_prompt = "test", response = "response" },
    })

    local ops = require("99.ops")
    local state = _99.__get_state()

    -- Call continue.run without additional_prompt
    local xid = continue_module.run(state, ops, source, {})

    -- Verify no request was made
    eq(nil, xid)
    eq(nil, provider.request)
  end)

  it("returns nil when additional_prompt is empty string", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    -- Create a source with turns
    local source = create_source_with_turns("vibe", {
      { user_prompt = "test", response = "response" },
    })

    local ops = require("99.ops")
    local state = _99.__get_state()

    -- Call continue.run with empty additional_prompt
    local xid = continue_module.run(state, ops, source, {
      additional_prompt = "",
    })

    -- Verify no request was made
    eq(nil, xid)
    eq(nil, provider.request)
  end)

  it("preserves session_id and turns in continued context", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    -- Create a source with multiple turns
    local source = create_source_with_turns("vibe", {
      { user_prompt = "first prompt", response = "first response" },
      { user_prompt = "second prompt", response = "second response" },
    })

    local original_session_id = source.session_id
    local original_turns_count = #source.turns

    local ops = require("99.ops")
    local state = _99.__get_state()

    -- Call continue.run
    continue_module.run(state, ops, source, {
      additional_prompt = "third prompt",
    })

    -- Verify the new context has the same session_id
    eq(original_session_id, provider.request.prompt.session_id)

    -- Verify the new context has the turns copied
    eq(original_turns_count, #provider.request.prompt.turns)
    eq("first prompt", provider.request.prompt.turns[1].user_prompt)
    eq("second prompt", provider.request.prompt.turns[2].user_prompt)
  end)

  it("returns nil when source is nil", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    local ops = require("99.ops")
    local state = _99.__get_state()

    -- Call continue.run with nil source
    local xid = continue_module.run(state, ops, nil, {
      additional_prompt = "test prompt",
    })

    -- Verify no request was made
    eq(nil, xid)
    eq(nil, provider.request)
  end)

  it("returns nil for unsupported source.operation", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    -- Create a source with an unsupported operation
    local source = Prompt.vibe(_99.__get_state())
    source.state = "success"
    source.operation = "unsupported_op"
    source:append_turn("test prompt", "test response")

    local ops = require("99.ops")
    local state = _99.__get_state()

    -- Call continue.run with unsupported operation
    local xid = continue_module.run(state, ops, source, {
      additional_prompt = "test follow up",
    })

    -- Verify no request was made
    eq(nil, xid)
    eq(nil, provider.request)
  end)

  it("uses only last 3 turns in continuation prompt", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    -- Create a source with 5 turns
    local source = create_source_with_turns("vibe", {
      { user_prompt = "first prompt", response = "first response" },
      { user_prompt = "second prompt", response = "second response" },
      { user_prompt = "third prompt", response = "third response" },
      { user_prompt = "fourth prompt", response = "fourth response" },
      { user_prompt = "fifth prompt", response = "fifth response" },
    })

    local ops = require("99.ops")
    local state = _99.__get_state()

    -- Call continue.run
    continue_module.run(state, ops, source, {
      additional_prompt = "sixth prompt",
    })

    -- Verify the query contains only the last 3 turns
    local query = provider.request.query

    -- Should NOT contain the first two turns
    assert.not_matches("first prompt", query, 1, true)
    assert.not_matches("first response", query, 1, true)
    assert.not_matches("second prompt", query, 1, true)
    assert.not_matches("second response", query, 1, true)

    -- Should contain the last 3 turns (3rd, 4th, 5th)
    assert.matches("third prompt", query, 1, true)
    assert.matches("third response", query, 1, true)
    assert.matches("fourth prompt", query, 1, true)
    assert.matches("fourth response", query, 1, true)
    assert.matches("fifth prompt", query, 1, true)
    assert.matches("fifth response", query, 1, true)

    -- Should contain the follow-up
    assert.matches("sixth prompt", query, 1, true)
  end)
end)

describe("_99.continue public API", function()
  after_each(function()
    test_utils.clean_files()
    -- Ensure we exit visual mode after each test
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
      "n",
      false
    )
  end)

  it(
    "continues latest successful vibe with last=true and additional_prompt",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))
      test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

      -- First, make a successful vibe request
      _99.vibe({ additional_prompt = "make this clearer" })
      provider:resolve("success", "first vibe response")
      test_utils.next_frame()

      -- Now continue it using the public API
      local xid =
        _99.continue({ last = true, additional_prompt = "less abstraction" })

      -- Verify a request was made
      assert(xid, "expected xid to be returned")
      assert(provider.request, "expected provider.request to be set")

      -- Verify the operation is vibe
      eq("vibe", provider.request.prompt.operation)

      -- Verify the stitched prompt contains the conversation history
      local query = provider.request.query
      assert.matches("make this clearer", query, 1, true)
      assert.matches("first vibe response", query, 1, true)
      assert.matches("less abstraction", query, 1, true)
    end
  )

  it(
    "captures last=true follow-up without mutating the source prompt",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))
      test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

      _99.vibe({ additional_prompt = "make this clearer" })
      provider:resolve("success", "first vibe response")
      test_utils.next_frame()

      local source = _99.__get_state().tracking:latest_successful("vibe")
      assert(source, "expected a successful source request")
      eq("make this clearer", source.user_prompt)

      local previous_capture_input = Window.capture_input
      Window.capture_input = function(_, opts)
        opts.cb(true, "less abstraction")
      end

      local ok, err = pcall(function()
        local xid = _99.continue({ last = true })

        eq(nil, xid)
        eq("make this clearer", source.user_prompt)
        assert(provider.request, "expected provider.request to be set")
        eq("vibe", provider.request.prompt.operation)
        assert.matches("less abstraction", provider.request.query, 1, true)
      end)

      Window.capture_input = previous_capture_input
      if not ok then
        error(err)
      end
    end
  )

  it(
    "captures selected follow-up without mutating the source prompt",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))
      test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

      _99.vibe({ additional_prompt = "make this clearer" })
      provider:resolve("success", "first vibe response")
      test_utils.next_frame()

      local source = _99.__get_state().tracking:latest_successful("vibe")
      assert(source, "expected a successful source request")
      eq("make this clearer", source.user_prompt)

      local previous_capture_input = Window.capture_input
      local previous_capture_select_input = Window.capture_select_input
      Window.capture_select_input = function(_, opts)
        opts.cb(true, opts.content[1])
      end
      Window.capture_input = function(_, opts)
        opts.cb(true, "less abstraction")
      end

      local ok, err = pcall(function()
        local xid = _99.continue()

        eq(nil, xid)
        eq("make this clearer", source.user_prompt)
        assert(provider.request, "expected provider.request to be set")
        eq("vibe", provider.request.prompt.operation)
        assert.matches("less abstraction", provider.request.query, 1, true)
      end)

      Window.capture_input = previous_capture_input
      Window.capture_select_input = previous_capture_select_input
      if not ok then
        error(err)
      end
    end
  )

  it("continues latest search by type even when newer vibe exists", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))
    test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

    -- First, make a successful search request
    _99.search({ additional_prompt = "find parser" })
    provider:resolve("success", "src/parser.lua:1: parser found")
    test_utils.next_frame()

    -- Then make a newer vibe request
    _99.vibe({ additional_prompt = "explain parser" })
    provider:resolve("success", "vibe response")
    test_utils.next_frame()

    -- Now continue the search (not the vibe) using type filter
    local xid = _99.continue({
      type = "search",
      last = true,
      additional_prompt = "narrow to tests",
    })

    -- Verify a request was made
    assert(xid, "expected xid to be returned")
    assert(provider.request, "expected provider.request to be set")

    -- Verify the operation is search (not vibe)
    eq("search", provider.request.prompt.operation)

    -- Verify the stitched prompt contains the search conversation history
    local query = provider.request.query
    assert.matches("find parser", query, 1, true)
    assert.matches("src/parser.lua:1: parser found", query, 1, true)
    assert.matches("narrow to tests", query, 1, true)
  end)

  it(
    "returns nil and does not call provider when no previous success exists",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))
      test_utils.create_file({ "local value = 1" }, "lua", 1, 0)

      -- Try to continue without any successful requests
      local xid = _99.continue({ last = true, additional_prompt = "try again" })

      -- Verify no request was made
      eq(nil, xid)
      eq(nil, provider.request)
    end
  )

  it(
    "refuses visual continuation without a current visual selection",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({
        in_flight_options = { enable = false },
      }, provider))

      -- Create a buffer with content and set up visual source
      local buffer = test_utils.create_file({ "local value = 1" }, "lua", 1, 0)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.cmd("normal! v$")

      local source = Prompt.visual(_99.__get_state())
      source.state = "success"
      source.user_prompt = "rewrite selection"
      source:append_turn("rewrite selection", "local value = 2")

      -- Exit visual mode - this is key for the test
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
        "n",
        false
      )
      test_utils.next_frame()

      local ops = require("99.ops")
      local state = _99.__get_state()

      -- Call continue.run - should refuse because we're not in visual mode
      local xid = continue_module.run(state, ops, source, {
        additional_prompt = "make it clearer",
      })

      -- Verify no request was made
      eq(nil, xid)
      eq(nil, provider.request)
    end
  )

  it("continues visual requests against the current selection", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({
      in_flight_options = { enable = false },
    }, provider))

    -- Create a buffer with content
    local buffer = test_utils.create_file({
      "local value = 1",
      "return value",
    }, "lua", 1, 0)

    -- First visual request: select first line
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v$")

    local source = Prompt.visual(_99.__get_state())
    source.state = "success"
    source.user_prompt = "rewrite selection"
    source:append_turn("rewrite selection", "local value = 2")

    -- Exit visual mode
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
      "n",
      false
    )
    test_utils.next_frame()

    local ops = require("99.ops")
    local state = _99.__get_state()

    -- Now set up a NEW visual selection for the continuation (second line)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("normal! v$")
    test_utils.next_frame()

    -- Call continue.run - should succeed because we have a fresh visual selection
    local xid = continue_module.run(state, ops, source, {
      additional_prompt = "rewrite return too",
    })

    -- Verify a request was made
    assert(xid, "expected xid to be returned")
    assert(provider.request, "expected provider.request to be set")

    -- Verify the operation is visual
    eq("visual", provider.request.prompt.operation)

    -- Verify the stitched prompt contains the conversation history
    local query = provider.request.query
    assert.matches("rewrite selection", query, 1, true)
    assert.matches("local value = 2", query, 1, true)
    assert.matches("rewrite return too", query, 1, true)
  end)
end)
