# openrouter.nvim

Minimal OpenRouter chat for Neovim.

## Install (Neovim 0.10+)

```lua
vim.pack.add({ { src = "https://github.com/0xinuarashi/openrouter.nvim" } })
```

## Setup

```lua
require("openrouter").setup({
  api_key = "YOUR_OPENROUTER_KEY",
  model = "openai/gpt-4o-mini",
  system_prompt = "You are a concise assistant.",
})
```

You can also set `OPENROUTER_API_KEY` in your environment.

## Usage

Run:

```
:AI <message>
```

The response streams into a floating window. When it finishes, keep typing and press `<CR>` to send the next message. Use `q` or `<Esc>` to close the window.

You can also run `:AI` with no arguments to open the chat window first.

## Options

- `api_key`: OpenRouter API key. If unset, uses `OPENROUTER_API_KEY`.
- `model`: OpenRouter model string. Default `openai/gpt-3.5-turbo`.
- `base_url`: OpenRouter endpoint. Default `https://openrouter.ai/api/v1/chat/completions`.
- `system_prompt`: Optional system message sent before the user message.
