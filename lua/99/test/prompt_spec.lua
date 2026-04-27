-- luacheck: globals describe it assert
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local Prompt = require("99.prompt")
local eq = assert.are.same

describe("prompt", function()
  it("should deserialize a serialized prompt", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({}, provider))

    local state = _99.__get_state()
    local prompt = Prompt.deserialize(state, {
      user_prompt = "find important changes",
      data = {
        type = "search",
        qfix_items = {},
        response = "",
      },
    })

    eq("search", prompt.operation)
    eq("search", prompt.data.type)
    eq("find important changes", prompt.user_prompt)
    eq("search: find important changes", prompt:summary())
  end)

  it("normalizes old serialized prompts into one-turn sessions", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({}, provider))

    local state = _99.__get_state()

    -- Test search type with response
    local search_prompt = Prompt.deserialize(state, {
      user_prompt = "search query",
      data = {
        type = "search",
        qfix_items = {},
        response = "search response",
      },
    })

    eq(1, #search_prompt.turns)
    eq("search query", search_prompt.turns[1].user_prompt)
    eq("search response", search_prompt.turns[1].response)
    assert.is_string(search_prompt.session_id)

    -- Test tutorial type with tutorial lines
    local tutorial_prompt = Prompt.deserialize(state, {
      user_prompt = "tutorial query",
      data = {
        type = "tutorial",
        buffer = 0,
        window = 0,
        xid = 1,
        tutorial = { "line 1", "line 2", "line 3" },
      },
    })

    eq(1, #tutorial_prompt.turns)
    eq("tutorial query", tutorial_prompt.turns[1].user_prompt)
    eq("line 1\nline 2\nline 3", tutorial_prompt.turns[1].response)

    -- Test vibe type with response
    local vibe_prompt = Prompt.deserialize(state, {
      user_prompt = "vibe query",
      data = {
        type = "vibe",
        qfix_items = {},
        response = "vibe response",
      },
    })

    eq(1, #vibe_prompt.turns)
    eq("vibe query", vibe_prompt.turns[1].user_prompt)
    eq("vibe response", vibe_prompt.turns[1].response)

    -- Test that new format with turns is preserved
    local new_format_prompt = Prompt.deserialize(state, {
      user_prompt = "new query",
      session_id = "session-123",
      data = {
        type = "search",
        qfix_items = {},
        response = "new response",
      },
      turns = {
        { user_prompt = "turn 1", response = "response 1" },
        { user_prompt = "turn 2", response = "response 2" },
      },
    })

    eq("session-123", new_format_prompt.session_id)
    eq(2, #new_format_prompt.turns)
    eq("turn 1", new_format_prompt.turns[1].user_prompt)
    eq("turn 2", new_format_prompt.turns[2].user_prompt)
  end)

  it("serializes session id and turns", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({}, provider))

    local state = _99.__get_state()
    local prompt = Prompt.search(state)
    prompt.user_prompt = "test query"
    prompt.state = "success"
    prompt.session_id = "test-session-456"
    prompt.turns = {
      { user_prompt = "query 1", response = "response 1" },
      { user_prompt = "query 2", response = "response 2" },
    }

    local serialized = prompt:serialize()

    eq("test-session-456", serialized.session_id)
    eq(2, #serialized.turns)
    eq("query 1", serialized.turns[1].user_prompt)
    eq("response 1", serialized.turns[1].response)
    eq("query 2", serialized.turns[2].user_prompt)
    eq("response 2", serialized.turns[2].response)
  end)

  it("returns recent turns without mutating stored turns", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({}, provider))

    local state = _99.__get_state()
    local prompt = Prompt.search(state)
    prompt.turns = {
      { user_prompt = "query 1", response = "response 1" },
      { user_prompt = "query 2", response = "response 2" },
      { user_prompt = "query 3", response = "response 3" },
      { user_prompt = "query 4", response = "response 4" },
      { user_prompt = "query 5", response = "response 5" },
    }

    -- Get last 3 turns
    local recent = prompt:recent_turns(3)

    eq(3, #recent)
    eq("query 3", recent[1].user_prompt)
    eq("query 4", recent[2].user_prompt)
    eq("query 5", recent[3].user_prompt)

    -- Verify original turns are unchanged
    eq(5, #prompt.turns)
    eq("query 1", prompt.turns[1].user_prompt)
    eq("query 5", prompt.turns[5].user_prompt)

    -- Verify modifying recent doesn't affect stored turns
    recent[1].user_prompt = "modified"
    eq("query 3", prompt.turns[3].user_prompt)

    -- Test with max larger than turns count
    local all_recent = prompt:recent_turns(10)
    eq(5, #all_recent)

    -- Test with max of 1
    local last_recent = prompt:recent_turns(1)
    eq(1, #last_recent)
    eq("query 5", last_recent[1].user_prompt)

    -- Test with max <= 0 returns empty table
    eq({}, prompt:recent_turns(0))
    eq({}, prompt:recent_turns(-1))
  end)

  it("round-trip serialization preserves data and runtime fields", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({}, provider))

    local state = _99.__get_state()

    -- Create a prompt with turns
    local original = Prompt.search(state)
    original.user_prompt = "round-trip test"
    original.state = "success"
    original.session_id = "round-trip-session-123"
    original.turns = {
      { user_prompt = "turn 1", response = "response 1" },
      { user_prompt = "turn 2", response = "response 2" },
    }

    -- Serialize
    local serialized = original:serialize()

    -- Verify serialized data
    eq("round-trip test", serialized.user_prompt)
    eq("round-trip-session-123", serialized.session_id)
    eq(2, #serialized.turns)
    eq("search", serialized.data.type)

    -- Deserialize
    local deserialized = Prompt.deserialize(state, serialized)

    -- Verify deserialized data matches original
    eq("round-trip test", deserialized.user_prompt)
    eq("round-trip-session-123", deserialized.session_id)
    eq(2, #deserialized.turns)
    eq("turn 1", deserialized.turns[1].user_prompt)
    eq("response 1", deserialized.turns[1].response)
    eq("turn 2", deserialized.turns[2].user_prompt)
    eq("response 2", deserialized.turns[2].response)
    eq("search", deserialized.operation)
    eq("search", deserialized.data.type)
    eq("success", deserialized.state)

    -- Verify runtime fields from set_defaults exist and are valid
    assert.is_number(deserialized.xid)
    assert.is_table(deserialized.logger)
    assert.is_string(deserialized.tmp_file)
    assert.is_table(deserialized.agent_context)
    assert.is_table(deserialized.clean_ups)
    assert.is_table(deserialized.marks)
    assert.is_table(deserialized.md_file_names)
    assert.is_string(deserialized.full_path)
    assert.is_number(deserialized.started_at)
  end)

  it("builds a continuation prompt from recent turns and follow-up", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({}, provider))

    local prompts = _99.__get_state().prompts.prompts
    local prompt = prompts.continue_chat("vibe", {
      { user_prompt = "make this clearer", response = "first answer" },
      { user_prompt = "less abstraction", response = "second answer" },
    }, "keep the original style")

    assert.matches("continuing a previous 99.vibe request", prompt, 1, true)
    assert.matches("make this clearer", prompt, 1, true)
    assert.matches("first answer", prompt, 1, true)
    assert.matches("less abstraction", prompt, 1, true)
    assert.matches("second answer", prompt, 1, true)
    assert.matches("keep the original style", prompt, 1, true)
    assert.matches(
      "Preserve the output format expected by 99.vibe",
      prompt,
      1,
      true
    )
  end)

  it("continue_chat includes TEMP_FILE instruction", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({}, provider))

    local prompts = _99.__get_state().prompts.prompts
    local prompt = prompts.continue_chat("tutorial", {
      { user_prompt = "explain this", response = "first explanation" },
    }, "go deeper")

    -- Verify the prompt includes TEMP_FILE instruction
    assert.matches("TEMP_FILE", prompt, 1, true)
    assert.matches("not provided conversationally", prompt, 1, true)
  end)

  it("serialize includes started_at and completed_at timestamps", function()
    local provider = test_utils.TestProvider.new()
    _99.setup(test_utils.get_test_setup_options({}, provider))

    local state = _99.__get_state()
    local prompt = Prompt.search(state)
    prompt.user_prompt = "timestamp test"
    prompt.state = "success"
    prompt.started_at = 1000
    prompt.completed_at = 2000

    local serialized = prompt:serialize()

    eq(1000, serialized.started_at)
    eq(2000, serialized.completed_at)
  end)

  it(
    "deserialize preserves started_at and completed_at from serialized data",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({}, provider))

      local state = _99.__get_state()
      local prompt = Prompt.deserialize(state, {
        user_prompt = "timestamp test",
        data = {
          type = "search",
          qfix_items = {},
          response = "",
        },
        started_at = 5000,
        completed_at = 6000,
      })

      eq(5000, prompt.started_at)
      eq(6000, prompt.completed_at)
    end
  )

  it(
    "deserialize keeps old serialized prompts valid without completed_at",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({}, provider))

      local state = _99.__get_state()
      local prompt = Prompt.deserialize(state, {
        user_prompt = "old format test",
        data = {
          type = "search",
          qfix_items = {},
          response = "",
        },
        -- No started_at or completed_at
      })

      -- Old serialized prompts did not store timestamps. They still get a runtime
      -- started_at from set_defaults, while completed_at remains absent so
      -- tracking can fall back to started_at without inventing completion order.
      assert.is_number(prompt.started_at)
      eq(nil, prompt.completed_at)
    end
  )

  it(
    "timestamp round-trip preserves values through serialize/deserialize",
    function()
      local provider = test_utils.TestProvider.new()
      _99.setup(test_utils.get_test_setup_options({}, provider))

      local state = _99.__get_state()

      -- Create a prompt with specific timestamps
      local original = Prompt.search(state)
      original.user_prompt = "round-trip timestamps"
      original.state = "success"
      original.started_at = 12345
      original.completed_at = 67890
      original.session_id = "test-session"
      original.turns = {
        { user_prompt = "query", response = "response" },
      }

      -- Serialize
      local serialized = original:serialize()

      -- Verify serialized timestamps
      eq(12345, serialized.started_at)
      eq(67890, serialized.completed_at)

      -- Deserialize
      local deserialized = Prompt.deserialize(state, serialized)

      -- Verify deserialized timestamps match original
      eq(12345, deserialized.started_at)
      eq(67890, deserialized.completed_at)
    end
  )
end)
