# 99
The AI client that Neovim deserves, built by those that still enjoy to code.

## IF YOU ARE HERE FROM [THE YT VIDEO](https://www.youtube.com/watch?v=ws9zR-UzwTE)
So many things have changed.  So please be careful!

## WARNING :: API CHANGES RIGHT NOW
It will happen that apis will disapear or be changed.  Sorry, this is an BETA product.

## Project Direction
This repo is meant to be my exploration grounds for using AI mixed with tradcoding.

I believe that hand coding is still very important and the best products i know
of today still do that (see opencode vs claude code)

## Warning
1. Prompts are temporary right now. they could be massively improved
2. Officially in beta, but api can still change.  unlikely at this point

# 99
The AI Neovim experience

## _99
99 is an agentic workflow that is meant to meld the current programmers ability
with the amazing powers of LLMs.  Instead of being a replacement, its meant to
augment the programmer.

As of now, the direction of 99 is to progress into agentic programming and surfacing
of information.  In the beginning and the original youtube video was about replacing
specific pieces of code.  The more i use 99 the more i realize the better use is
through `search` and `work`

### Basic Setup
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
                -- provider = _99.Providers.ClaudeCodeProvider,  -- default: OpenCodeProvider
				logger = {
					level = _99.DEBUG,
					path = "/tmp/" .. basename .. ".99.debug",
					print_on_error = true,
				},
                -- When setting this to something that is not inside the CWD tools
                -- such as claude code or opencode will have permission issues
                -- and generation will fail refer to tool documentation to resolve
                -- https://opencode.ai/docs/permissions/#external-directories
                -- https://code.claude.com/docs/en/permissions#read-and-edit
                tmp_dir = "./tmp",

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
                    --- File Discovery:
                    --- - In git repos: Uses `git ls-files` which automatically respects .gitignore
                    --- - Non-git repos: Falls back to filesystem scanning with manual excludes
                    --- - Both methods apply the configured `exclude` list on top of gitignore

                    --- What autocomplete engine to use. Defaults to native (built-in) if not specified.
                    source = "native", -- "native" (default), "cmp", or "blink"
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
			vim.keymap.set("n", "<leader>9x", function()
				_99.stop_all_requests()
			end)

			vim.keymap.set("n", "<leader>9s", function()
				_99.search()
			end)
		end,
	},
```

### Usage
I would highly recommend trying out `search` as its the direction the library is going

```lua
_99.search()
```

See search for more details

### Description
| Name                      | Type                                           | Default Value |
| ------------------------- | ---------------------------------------------- | ------------- |
| `setup`                   | `fun(opts?: _99.Options): nil`                 | -             |
| `search`                  | `fun(opts: _99.ops.SearchOpts): _99.TraceID`   | -             |
| `vibe`                    | `fun(opts?: _99.ops.Opts): _99.TraceID \| nil` | -             |
| `open`                    | `fun(): nil`                                   | -             |
| `visual`                  | `fun(opts: _99.ops.Opts): _99.TraceID`         | -             |
| `view_logs`               | `fun(): nil`                                   | -             |
| `stop_all_requests`       | `fun(): nil`                                   | -             |
| `clear_previous_requests` | `fun(): nil`                                   | -             |
| `Extensions`              | `_99.Extensions`                               | -             |

### API

#### setup
Sets up _99.  Must be called for this library to work.  This is how we setup
in flight request spinners, set default values, get completion to work the
way you want it to.

#### search
Performs a search across your project with the prompt you provide and return out a list of
locations with notes that will be put into your quick fix list.

#### vibe
No description.

#### open
Opens a selection window for you to select the last interaction to open
and display its contents in a way that makes sense for its type.  For
search and vibe, it will open the qfix window.  For tutorial, it will open
the tutorial window.

#### visual
takes your current selection and sends that along with the prompt provided and replaces
your visual selection with the results

#### view_logs
views the most recent logs and setups the machine to view older and new logs
this is still pretty rough and will change in the near future

#### stop_all_requests
stops all in flight requests.  this means that the underlying process will
be killed (OpenCode) and any result will be discared

#### clear_previous_requests
clears all previous search and visual operations

#### Extensions
check out Worker for cool abstraction on search and vibe

## _99.Extensions.Worker
A persistent way to keep track of work.

this will likely be where the most change and focus goes into.  I would like
to take this into worktree territory and be able to swap between stuff super
slick.

Until then, it is going to be a single bit of work that you can provide
the description and then use search to find what is left that needs to be done.

### Description
| Name       | Type                            | Default Value |
| ---------- | ------------------------------- | ------------- |
| `set_work` | `fun(opts?: _99.WorkOpts): nil` | -             |
| `search`   | `fun(): nil`                    | -             |

### API

#### set_work
will set the work for the project.  If opts provide a description then no
input capture of work description will be required

#### search
will use _99.search to find what is left to be done for this work item to be
considered done

## _99.Options
No description.

### Description
| Name                | Type                                | Default Value |
| ------------------- | ----------------------------------- | ------------- |
| `logger`            | `_99.Logger.Options \| nil`         | -             |
| `model`             | `string \| nil`                     | -             |
| `in_flight_options` | `_99.InFlight.Opts \| nil`          | -             |
| `md_files`          | `string[] \| nil`                   | -             |
| `provider`          | `_99.Providers.BaseProvider \| nil` | -             |
| `display_errors`    | `boolean \| nil`                    | -             |
| `auto_add_skills`   | `boolean \| nil`                    | -             |
| `completion`        | `_99.Completion \| nil`             | -             |
| `tmp_dir`           | `string \| nil`                     | -             |

### API

#### logger
No description.

#### model
No description.

#### in_flight_options
No description.

#### md_files
No description.

#### provider
No description.

#### display_errors
No description.

#### auto_add_skills
No description.

#### completion
No description.

#### tmp_dir
No description.

## _99.ops.Opts
The options that are used throughout all the interations with 99.  This
includes search, visual, and others

### Description
| Name                | Type                       | Default Value |
| ------------------- | -------------------------- | ------------- |
| `additional_prompt` | `string \| nil`            | -             |
| `additional_rules`  | `_99.Agents.Rule[] \| nil` | -             |

### API

#### additional_prompt
by providing `additional_prompt` you will not be required to provide a prompt.
this allows you to define actions based on remaps

```lua
remap("n", "<leader>9d", function()
  --- this function could be used to auto debug your project
  _99.search({
    additional_prompt = [[
run `make test` and debug the test failures and provide me a comprehensive set of steps where
the tests are breaking ]]
  })
end)
```

This would kick off a search job that will run your tests in the background.
the resulting failures would be diagnosed and search results would be transfered
into a quick fix list.

#### additional_rules
can be used to provide extra args.  If you have a skill called "cloudflare" you could
provide the rule for cloudflare and its context will be injected into your request

## _99.ops.SearchOpts
See `_99.opts.Opts` for more information.

There are no properties yet.  But i would like to tweek some behavior based on opts

### Description
| Name | Type | Default Value |
| ---- | ---- | ------------- |
| -    | -    | -             |

### API
No properties.

## _99.WorkOpts
No description.

### Description
| Name          | Type            | Default Value |
| ------------- | --------------- | ------------- |
| `description` | `string \| nil` | -             |

### API

#### description
No description.

## _99.Completion
No description.

### Description
| Name           | Type                      | Default Value |
| -------------- | ------------------------- | ------------- |
| `source`       | `"cmp" \| "blink" \| nil` | -             |
| `custom_rules` | `string[]`                | -             |
| `files`        | `_99.Files.Config?`       | -             |

### API

#### source
No description.

#### custom_rules
No description.

#### files
No description.

## _99.InFlight.Opts
this is pure a class for testing.   helps controls timings

### Description
| Name                 | Type                       | Default Value |
| -------------------- | -------------------------- | ------------- |
| `throbber_opts`      | `_99.Throbber.Opts \| nil` | -             |
| `in_flight_interval` | `number \| nil`            | -             |
| `enable`             | `boolean \| nil`           | -             |

### API

#### throbber_opts
options for the throbber in the top left

#### in_flight_interval
frequency in which the in-flight interval checks to see if it should be
displayed / removed

#### enable
defaults to true

## _99.Logger.Options
No description.

### Description
| Name                  | Type                                 | Default Value |
| --------------------- | ------------------------------------ | ------------- |
| `level`               | `number?`                            | -             |
| `type`                | `"print" \| "void" \| "file" \| nil` | -             |
| `path`                | `string?`                            | -             |
| `print_on_error`      | `boolean \| nil`                     | -             |
| `max_requests_cached` | `number \| nil`                      | -             |

### API

#### level
No description.

#### type
No description.

#### path
No description.

#### print_on_error
No description.

#### max_requests_cached
No description.

## _99.Agents.Rule
No description.

### Description
| Name            | Type      | Default Value |
| --------------- | --------- | ------------- |
| `name`          | `string`  | -             |
| `path`          | `string`  | -             |
| `absolute_path` | `string?` | -             |

### API

#### name
No description.

#### path
No description.

#### absolute_path
No description.

## Completions

When prompting, you can reference rules and files to add context to your request.

- `#` references rules — type `#` in the prompt to autocomplete rule files from your configured rule directories
- `@` references files — type `@` to fuzzy-search project files. This will exclude files that are in .gitignore.

Referenced content is automatically resolved and injected into the AI context. Native completions work by default. For nvim-cmp or blink.cmp, set `source = "cmp"` or `source = "blink"`.

## Providers
99 supports multiple AI CLI backends. Set `provider` in your setup to switch. If you don't set `model`, the provider's default is used.

| Provider                     | CLI tool       | Default model                |
| ---------------------------- | -------------- | ---------------------------- |
| `OpenCodeProvider` (default) | `opencode`     | `opencode/claude-sonnet-4-5` |
| `ClaudeCodeProvider`         | `claude`       | `claude-sonnet-4-5`          |
| `CursorAgentProvider`        | `cursor-agent` | `sonnet-4.5`                 |
| `KiroProvider`               | `kiro-cli`     | `auto`                       |
| `GeminiCLIProvider`          | `gemini`       | `auto`                       |

```lua
_99.setup({
    provider = _99.Providers.ClaudeCodeProvider,
    -- model is optional, overrides the provider's default
    model = "claude-sonnet-4-5",
})
```

## Extensions

### Telescope Model Selector

If you have [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed, you can switch models on the fly via the Telescope picker:

```lua
vim.keymap.set("n", "<leader>9m", function()
  require("99.extensions.telescope").select_model()
end)
```

The selected model is used for all subsequent requests in the current session.

### Telescope Provider Selector

Switch between providers (OpenCode, Claude, Cursor, Kiro) without restarting Neovim. Switching provider also resets the model to that provider's default.

```lua
vim.keymap.set("n", "<leader>9p", function()
  require("99.extensions.telescope").select_provider()
end)
```

### fzf-lua

If you use [fzf-lua](https://github.com/ibhagwan/fzf-lua) instead of telescope, the same pickers are available:

```lua
vim.keymap.set("n", "<leader>9m", function()
  require("99.extensions.fzf_lua").select_model()
end)

vim.keymap.set("n", "<leader>9p", function()
  require("99.extensions.fzf_lua").select_provider()
end)
```

## Reporting a bug

To report a bug, please provide the full running debug logs. This may require
a bit of back and forth.

Please do not request features. We will hold a public discussion on Twitch about
features, which will be a much better jumping point then a bunch of requests that i have to close down. If you do make a feature request ill just shut it down instantly.

### The logs
To get the _last_ run's logs execute `:lua require("99").view_logs()`.

### Dont forget
If there are secrets or other information in the logs you want to be removed make
sure that you delete the `query` printing. This will likely contain information you may not want to share.

