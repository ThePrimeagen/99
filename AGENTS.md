- always use neovim provided functions
- this is not a standard lua project. package resolution and all things related to lua and std should be ignored in favor of neovim and its utitlites.

## Testing

- make lua_test
- make pr_ready

## e2e / Integration style testing

every testing file should have roughly the same setup.

```lua
-- In this example we are testing the visual function for 99 requests
-- test utils has utilities to setup buffers and request context and
-- test providers that we can control when to resolve
-- test utils also has functions to schedule syncronously, very powerful
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local visual_fn = require("99.ops.over-range")
-- ... imports that need to be tested

describe("<name of test group>", function()

    it("specific test condition", function()
        -- we setup the world with test provider, context, and state
        local p, buffer, range = setup(content, 2, 1, 2, 23)
        local state = _99.__get_state()
        local context = Prompt.visual(state)

        -- now this test is simple, its just proving that we keep track
        -- of inflight requests.
        --
        -- all tests should have simple conditions we are testing for
        -- and the logic should attempt to be as simple as possible.
    eq(0, state:active_request_count())
      visual_fn(context, {
        additional_prompt = "test prompt",
      })
    eq(1, state:active_request_count())
    p:resolve("success", "    return 'implemented!'")
    test_utils.next_frame()
    eq(0, state:active_request_count())

    end)
end)
```
