local ok, ai = pcall(require, "ai_openrouter")
if not ok then
  return
end

vim.api.nvim_create_user_command("AI", function(opts)
  local message = opts.args or ""
  if message == "" then
    vim.notify("Usage: :AI <message>", vim.log.levels.INFO)
    return
  end
  ai.ask(message)
end, { nargs = "+" })
