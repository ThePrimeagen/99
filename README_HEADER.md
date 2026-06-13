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

___DOCS___

## Completions

When prompting, you can reference rules and files to add context to your request.

- `#` references rules — type `#` in the prompt to autocomplete rule files from your configured rule directories
- `@` references files — type `@` to fuzzy-search project files

Referenced content is automatically resolved and injected into the AI context. Requires cmp (`source = "cmp"` in your completion config).

## Providers
99 supports multiple AI CLI backends. Set `provider` in your setup to switch. If you don't set `model`, the provider's default is used.

| Provider | CLI tool | Default model |
|---|---|---|
| `OpenCodeProvider` (default) | `opencode` | `opencode/claude-sonnet-4-5` |
| `ClaudeCodeProvider` | `claude` | `claude-sonnet-4-5` |
| `CursorAgentProvider` | `cursor-agent` | `sonnet-4.5` |
| `GeminiCLIProvider` | `gemini` | `auto` |

```lua
_99.setup({
    provider = _99.Providers.ClaudeCodeProvider,
    -- model is optional, overrides the provider's default
    model = "claude-sonnet-4-5",
})
```

## Extensions

### Model Selector

99 uses `vim.ui.select()` for model and provider selection, so it will work with whatever UI backend you have configured for that API.

```lua
vim.keymap.set("n", "<leader>9m", function()
  require("99.extensions.pickers").select_model()
end)
```

The selected model is used for all subsequent requests in the current session.

### Provider Selector

Switch between providers (OpenCode, Claude, Cursor, Kiro) without restarting Neovim. Switching provider also resets the model to that provider's default.

```lua
vim.keymap.set("n", "<leader>9p", function()
  require("99.extensions.pickers").select_provider()
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
