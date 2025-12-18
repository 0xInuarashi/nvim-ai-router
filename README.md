# nvim-ai-openrouter

Minimal OpenRouter chat for Neovim.

## Install (Neovim 0.10+)

```lua
vim.pack.add({ { src = "/home/dev/git/0xinuarashi/nvim-ai-router" } })
```

## Setup

```lua
require("ai_openrouter").setup({
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

The response opens in a split buffer.

## Options

- `api_key`: OpenRouter API key. If unset, uses `OPENROUTER_API_KEY`.
- `model`: OpenRouter model string. Default `openai/gpt-3.5-turbo`.
- `base_url`: OpenRouter endpoint. Default `https://openrouter.ai/api/v1/chat/completions`.
- `system_prompt`: Optional system message sent before the user message.
