local ok, ai = pcall(require, "openrouter")
if not ok then
  return
end

vim.api.nvim_create_user_command("AI", function(opts)
  local message = opts.args or ""
  if message == "" then
    ai.open_chat()
    return
  end
  ai.ask(message)
end, { nargs = "*" })
