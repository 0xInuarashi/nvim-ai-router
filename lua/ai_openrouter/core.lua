local M = {}

M.config = {
  api_key = nil,
  model = "openai/gpt-3.5-turbo",
  base_url = "https://openrouter.ai/api/v1/chat/completions",
  system_prompt = nil,
}

local function get_api_key()
  if M.config.api_key and M.config.api_key ~= "" then
    return M.config.api_key
  end
  local env_key = vim.env.OPENROUTER_API_KEY
  if env_key and env_key ~= "" then
    return env_key
  end
  return nil
end

local function normalize_lines(lines)
  local out = {}
  for _, line in ipairs(lines) do
    if line == nil then
      -- skip
    else
      local parts = vim.split(tostring(line), "\n", { plain = true })
      for _, part in ipairs(parts) do
        table.insert(out, part)
      end
    end
  end
  return out
end

local function append_chat(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local safe_lines = normalize_lines(lines)

  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count > 0 and vim.bo[buf].buftype == "prompt" then
    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, {})
  end

  vim.api.nvim_buf_set_lines(buf, -1, -1, false, safe_lines)

  if vim.bo[buf].buftype == "prompt" then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
  end

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
  end
end


local function parse_response(stdout)
  local ok, decoded = pcall(vim.fn.json_decode, stdout)
  if not ok or type(decoded) ~= "table" then
    return nil, "failed to parse response"
  end

  local choice = decoded.choices and decoded.choices[1]
  if not choice or not choice.message or not choice.message.content then
    return nil, "missing response content"
  end

  return choice.message.content, nil
end

local function request(messages, cb)
  local api_key = get_api_key()
  if not api_key then
    vim.schedule(function()
      cb(nil, "missing OpenRouter API key")
    end)
    return
  end

  local payload = vim.fn.json_encode({
    model = M.config.model,
    messages = messages,
  })

  local cmd = {
    "curl",
    "-sS",
    "-X",
    "POST",
    M.config.base_url,
    "-H",
    "Authorization: Bearer " .. api_key,
    "-H",
    "Content-Type: application/json",
    "-d",
    payload,
  }

  if vim.system then
    vim.system(cmd, { text = true }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          cb(nil, res.stderr ~= "" and res.stderr or "request failed")
          return
        end

        local content, err = parse_response(res.stdout)
        cb(content, err)
      end)
    end)
    return
  end

  local stdout = {}
  local stderr = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        table.insert(stdout, table.concat(data, "\n"))
      end
    end,
    on_stderr = function(_, data)
      if data then
        table.insert(stderr, table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          cb(nil, table.concat(stderr, "\n"))
          return
        end

        local content, err = parse_response(table.concat(stdout, "\n"))
        cb(content, err)
      end)
    end,
  })
end

local function on_input(buf, input)
  if not input or input == "" then
    return
  end

  local messages = { { role = "user", content = input } }
  append_chat(buf, { "You: " .. input, "" })

  request(messages, function(content, err)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    if err then
      append_chat(buf, { "Error: " .. err, "" })
      return
    end

    append_chat(buf, { "AI: " .. content, "" })
  end)
end

function M.open_chat()
  local api_key = get_api_key()
  if not api_key then
    vim.notify("OpenRouter API key not set", vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "AI Chat")
  vim.bo[buf].buftype = "prompt"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "ai_openrouter"
  vim.bo[buf].modifiable = true
  vim.bo[buf].undolevels = -1

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_option(0, "wrap", true)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "OpenRouter Chat",
    "Enter a message and press <CR>. Use :q to close.",
    "",
    "",
  })

  vim.fn.prompt_setprompt(buf, "You: ")
  vim.fn.prompt_setcallback(buf, function(input)
    on_input(buf, input)
  end)

  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
  vim.cmd("startinsert")
end

function M.ask(message)
  local api_key = get_api_key()
  if not api_key then
    vim.notify("OpenRouter API key not set", vim.log.levels.ERROR)
    return
  end

  vim.notify("Q: " .. message)

  local messages = {}
  if M.config.system_prompt and M.config.system_prompt ~= "" then
    table.insert(messages, { role = "system", content = M.config.system_prompt })
  end
  table.insert(messages, { role = "user", content = message })
  request(messages, function(content, err)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    vim.notify("A: " .. content)
  end)
end

function M.setup(opts)
  if opts and type(opts) == "table" then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
end

return M
