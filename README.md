## The AI Agent That Neovim Deserves
This is an example repo where i want to test what i think the ideal AI workflow
is for people who dont have "skill issues."  This is meant to streamline the requests to AI and limit them it restricted areas.  For more general requests, please just use opencode.  Dont use neovim.

## Warning
1. Prompts are temporary right now. they could be massively improved
2. TS and Lua language support, open to more
3. Still very alpha, could have severe problems

## How to use
**you must have opencode installed and setup**

Add the following configuration to your neovim config

I make the assumption you are using Lazy
```lua
	{
		"ThePrimeagen/99",
		config = function()
			local _99 = require("99")

            -- For logging that is to a file if you wish to trace through requests
            -- for reporting bugs, i would not rely on this, but instead the provided
            -- logging mechanisms within 99.  This is for more debugging purposes
            local cwd = vim.uv.cwd()
            local basename = vim.fs.basename(cwd)
			_99.setup({
				logger = {
					level = _99.DEBUG,
					path = "/tmp/" .. basename .. ".99.debug",
					print_on_error = true,
				},

                --- WARNING: if you change cwd then this is likely broken
                --- ill likely fix this in a later change
                ---
                --- md_files is a list of files to look for and auto add based on the location
                --- of the originating request.  That means if you are at /foo/bar/baz.lua
                --- the system will automagically look for:
                --- /foo/bar/AGENT.md
                --- /foo/AGENT.md
                --- assuming that /foo is project root (based on cwd)
				md_files = {
					"AGENT.md",
				},
			})

            -- Create your own short cuts for the different types of actions
			vim.keymap.set("n", "<leader>9f", function()
				_99.fill_in_function()
			end)
            -- take extra note that i have visual selection only in v mode
            -- technically whatever your last visual selection is, will be used
            -- so i have this set to visual mode so i dont screw up and use an
            -- old visual selection
            --
            -- likely ill add a mode check and assert on required visual mode
            -- so just prepare for it now
			vim.keymap.set("v", "<leader>9v", function()
				_99.visual()
			end)

            --- if you have a request you dont want to make any changes, just cancel it
			vim.keymap.set("v", "<leader>9s", function()
				_99.stop_all_requests()
			end)

            -- Mode switching (Code vs Writer)
            vim.keymap.set("n", "<leader>9t", function()
                _99.toggle_mode()
            end)

            -- Check current status (Mode, Language, etc)
            vim.keymap.set("n", "<leader>9i", function()
                _99.info()
            end)

            -- Select model from available opencode models
            vim.keymap.set("n", "<leader>9m", function()
                _99.select_model()
            end)
		end,
	},
```

## Modes of Operation

99 has two primary modes: **Code Assistant** and **Writer's Assistant**.

### Code Assistant (Default)
Focused on software engineering tasks. It expects code context and provides canonical, robust implementations.

### Writer's Assistant
Designed for text editing, correction, and creative writing. It acts as a professional editor to improve clarity, flow, and grammar. It checks the `:set spelllang` of your current buffer. If no spelllang is set, it falls back to your system's `$LANG`. Also, you can override this with `:lua require("99").set_writer_language("pt-BR")`.

### Toggle between modes
To switch modes, use `require("99").toggle_mode()` or `require("99").set_mode("writer")`.

## Model Selection
You can dynamically change the model being used by 99. By default, it uses `opencode/claude-sonnet-4-5`. To see a list of available models and pick one: `:lua require("99").select_model()`.This will query `opencode` for all available models and present them using `vim.ui.select`.

## API
You can see the full api at [99 API](./lua/99/init.lua)

## Reporting a bug
To report a bug, please provide the full running debug logs.  This may require
a bit of back and forth.

Please do not request features.  We will hold a public discussion on Twitch about
features, which will be a much better jumping point then a bunch of requests that i have to close down.  If you do make a feature request ill just shut it down instantly.

### The logs
To get the _last_ run's logs execute `:lua require("99").view_logs()`.  If this happens to not be the log, you can navigate the logs with:

```lua
function _99.prev_request_logs() ... end
function _99.next_request_logs() ... end
```

### Dont forget
If there are secrets or other information in the logs you want to be removed make sure that you delete the `query` printing.  This will likely contain information you may not want to share.

### The Great Twitch Discussion
I will conduct a stream on Jan 30 at 11am The Lords Time (Montana Time/Mountain Time (same thing))
we will do an extensive deep dive on 99 and what we think is good and bad.

### Known usability issues
* long function definition issues.
```typescript
function display_text(
  game_state: GameState,
  text: string,
  x: number,
  y: number,
): void {
  const ctx = game_state.canvas.getContext("2d");
  assert(ctx, "cannot get game context");
  ctx.fillStyle = "white";
  ctx.fillText(text, x, y);
}
```

Then the virtual text will be displayed one line below "function" instead of first line in body

* in lua and likely jsdoc, the replacing function will duplicate comment definitions
  * this wont happen in languages with types in the syntax

* visual selection sends the whole file.  there is likely a better way to use
  treesitter to make the selection of the content being sent more sensible.

* for both fill in function and visual there should be a better way to gather
context.  I think that treesitter + lsp could be really powerful.  I am going
to experiment with this more once i get access to the FIM models.  This could
make the time to completion less than a couple seconds, which would be
incredible

* every now and then the replacement seems to get jacked up and it screws up
what i am currently editing..  I think it may have something to do with auto-complete
  * definitely not suure on this one

* export function ... sometimes gets export as well.  I think the prompt could help prevent this
