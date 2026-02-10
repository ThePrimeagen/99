# IF YOU ARE HERE FROM [THE YT VIDEO](https://www.youtube.com/watch?v=ws9zR-UzwTE)
a few things changed.  completion is a bit different for skills.  i now require `@` to begin with
... ill try to update as it happens ...

# WARNING :: API CHANGES RIGHT NOW
It will happen that apis will disapear or be changed.  Sorry, this is an ALPHA product.

# 99
The AI client that Neovim deserves, built by those that still enjoy to code.

# API
* visual
* search (upcoming, not ready yet)
* debug (planned)

## The AI Agent That Neovim Deserves
This is an example repo where i want to test what i think the ideal AI workflow
is for people who dont have "skill issues."  This is meant to streamline the requests to AI and limit them it restricted areas.  For more general requests, please just use opencode.  Dont use neovim.


## Warning
1. Prompts are temporary right now. they could be massively improved
2. TS and Lua language support, open to more
3. Still very alpha, could have severe problems

## How to use
**you must have a supported AI CLI installed (opencode, claude, or cursor-agent — see [Providers](#providers) below)**

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
                -- provider = _99.ClaudeCodeProvider,  -- default: OpenCodeProvider
				logger = {
					level = _99.DEBUG,
					path = "/tmp/" .. basename .. ".99.debug",
					print_on_error = true,
				},

                --- Completions: #rules and @files in the prompt buffer
                completion = {
                    -- I am going to disable these until i understand the
                    -- problem better.  Inside of cursor rules there is also
                    -- application rules, which means i need to apply these
                    -- differently
                    -- cursor_rules = "<custom path to cursor rules>"

                    --- A list of folders where you have your own SKILL.md
                    --- Expected format:
                    --- /path/to/dir/<skill_name>/SKILL.md
                    ---
                    --- Example:
                    --- Input Path:
                    --- "scratch/custom_rules/"
                    ---
                    --- Output Rules:
                    --- {path = "scratch/custom_rules/vim/SKILL.md", name = "vim"},
                    --- ... the other rules in that dir ...
                    ---
                    custom_rules = {
                      "scratch/custom_rules/",
                    },

                    --- Configure @file completion (all fields optional, sensible defaults)
                    files = {
                        -- enabled = true,
                        -- max_file_size = 102400,     -- bytes, skip files larger than this
                        -- max_files = 5000,            -- cap on total discovered files
                        -- exclude = { ".env", ".env.*", "node_modules", ".git", ... },
                    },

                    --- What autocomplete do you use.  We support:
                    --- "cmp" - nvim-cmp
                    --- "blink" - blink.cmp
                    source = "cmp",
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
		end,
	},
```

## Completions
When prompting, you can reference rules and files to add context to your request.
Both **nvim-cmp** and **blink.cmp** are supported.

- `#` references rules — type `#` in the prompt to autocomplete rule files from your configured rule directories
- `@` references files — type `@` to fuzzy-search project files

Referenced content is automatically resolved and injected into the AI context. Set `source = "cmp"` or `source = "blink"` in your completion config.

## Providers
99 supports multiple AI CLI backends. Set `provider` in your setup to switch. If you don't set `model`, the provider's default is used.

| Provider | CLI tool | Default model |
|---|---|---|
| `OpenCodeProvider` (default) | `opencode` | `opencode/claude-sonnet-4-5` |
| `ClaudeCodeProvider` | `claude` | `claude-sonnet-4-5` |
| `CursorAgentProvider` | `cursor-agent` | `sonnet-4.5` |

```lua
_99.setup({
    provider = _99.ClaudeCodeProvider,
    -- model is optional, overrides the provider's default
    model = "claude-sonnet-4-5",
})
```

### nvim-cmp
Set `source = "cmp"` in your completion config (shown in example above).

### blink.cmp
Set `source = "blink"` in your completion config, then add the 99 source to your blink.cmp setup:

```lua
require("blink.cmp").setup({
  sources = {
    default = { "lsp", "path", "snippets", "buffer", "99" },
    providers = {
      ["99"] = {
        module = "99.extensions.completions.blink",
        name = "99",
      },
    },
  },
})
```

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

* every now and then the replacement seems to get jacked up and it screws up
what i am currently editing..  I think it may have something to do with auto-complete
  * definitely not suure on this one

* export function ... sometimes gets export as well.  I think the prompt could help prevent this
