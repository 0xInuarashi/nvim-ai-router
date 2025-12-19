local M = {}
local chat = nil

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

local function sanitize_message(text)
  if not text then
    return ""
  end
  return tostring(text):gsub("[%z\1-\8\11\12\13\14-\31\127]", "")
end

local function validate_base_url(url)
  if type(url) ~= "string" or url == "" then
    return nil, "invalid base_url"
  end
  if url:sub(1, 1) == "-" then
    return nil, "base_url must not start with '-'"
  end
  if not url:match("^https://") then
    return nil, "base_url must start with https://"
  end
  return url, nil
end

local function build_curl_config(url, api_key, extra_headers)
  local lines = {
    "url = " .. url,
    "request = POST",
    "header = \"Authorization: Bearer " .. api_key .. "\"",
    "header = \"Content-Type: application/json\"",
    "silent",
    "show-error",
  }
  if extra_headers then
    for _, header in ipairs(extra_headers) do
      table.insert(lines, "header = \"" .. header .. "\"")
    end
  end
  return lines
end

local function request_stream(messages, on_chunk, on_done)
  local api_key = get_api_key()
  if not api_key then
    vim.schedule(function()
      on_done(nil, "missing OpenRouter API key")
    end)
    return
  end

  local url, url_err = validate_base_url(M.config.base_url)
  if not url then
    vim.schedule(function()
      on_done(nil, url_err)
    end)
    return
  end

  local payload = {
    model = M.config.model,
    messages = messages,
    stream = true,
  }

  local config_lines = build_curl_config(url, api_key, { "Accept: text/event-stream" })
  local config_path = vim.fn.tempname()
  vim.fn.writefile(config_lines, config_path)

  local payload_json = vim.fn.json_encode(payload)

  local cmd = {
    "curl",
    "--config",
    config_path,
    "--no-buffer",
    "--data-binary",
    "@-",
  }

  local stdout = {}
  local stderr = {}
  local done = false
  local response = ""

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = true,
    stdin = "pipe",
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line and line ~= "" then
          local payload_line = line:match("^data:%s*(.*)")
          if payload_line then
            if payload_line == "[DONE]" then
              done = true
              vim.schedule(function()
                on_done(response, nil)
              end)
              return
            end
            local ok, decoded = pcall(vim.fn.json_decode, payload_line)
            if ok and decoded then
              if decoded.error then
                local msg = decoded.error.message or decoded.error.type or "request failed"
                done = true
                vim.schedule(function()
                  on_done(nil, msg)
                end)
                return
              end
              local choice = decoded.choices and decoded.choices[1]
              local delta = ""
              if choice and choice.delta and choice.delta.content then
                delta = choice.delta.content
              elseif choice and choice.message and choice.message.content then
                delta = choice.message.content
              end
              if delta ~= "" then
                response = response .. delta
                vim.schedule(function()
                  on_chunk(delta, response)
                end)
              end
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        table.insert(stderr, table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        pcall(vim.loop.fs_unlink, config_path)
        if done then
          return
        end
        if code ~= 0 then
          on_done(nil, table.concat(stderr, "\n"))
          return
        end
        on_done(response, nil)
      end)
    end,
  })
  if job_id > 0 then
    vim.fn.chansend(job_id, payload_json)
    vim.fn.chanclose(job_id, "stdin")
  else
    pcall(vim.loop.fs_unlink, config_path)
    on_done(nil, "failed to start request")
  end
end

local send_current_input

local function ensure_chat()
  if chat and vim.api.nvim_buf_is_valid(chat.buf) and vim.api.nvim_win_is_valid(chat.win) then
    vim.api.nvim_set_current_win(chat.win)
    return chat
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "openrouter"
  vim.bo[buf].modifiable = true

  local width = math.max(60, math.floor(vim.o.columns * 0.7))
  local height = math.max(14, math.floor(vim.o.lines * 0.6))
  width = math.min(width, vim.o.columns - 4)
  height = math.min(height, vim.o.lines - 4)

  local row = math.floor((vim.o.lines - height) / 2 - 1)
  if row < 0 then
    row = 0
  end
  local col = math.floor((vim.o.columns - width) / 2)
  if col < 0 then
    col = 0
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })
  vim.api.nvim_win_set_option(win, "wrap", true)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "You: " })

  chat = {
    buf = buf,
    win = win,
    messages = {},
    streaming = false,
    assistant_start = nil,
  }

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })

  vim.keymap.set("n", "<CR>", function()
    send_current_input(chat)
  end, { buffer = buf, silent = true, nowait = true })

  vim.keymap.set("i", "<CR>", function()
    send_current_input(chat)
  end, { buffer = buf, silent = true, nowait = true })

  return chat
end

local function render_response(state, response)
  if not state or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local parts = vim.split(response or "", "\n", { plain = true })
  if #parts == 0 then
    parts = { "" }
  end

  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local new_lines = {}
  for i = 1, (state.assistant_start or 1) - 1 do
    new_lines[i] = lines[i]
  end
  new_lines[state.assistant_start] = "AI: " .. parts[1]
  for i = 2, #parts do
    new_lines[state.assistant_start + i - 1] = parts[i]
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, new_lines)
  if vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { #new_lines, 0 })
  end
end

local function append_prompt(state)
  if not state or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  table.insert(lines, "")
  table.insert(lines, "You: ")
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  if vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { #lines, 0 })
    vim.cmd("startinsert")
  end
end

send_current_input = function(state)
  if not state or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  if state.streaming then
    vim.notify("Waiting for response...", vim.log.levels.INFO)
    return
  end

  local line = vim.api.nvim_buf_get_lines(state.buf, -1, -1, false)[1] or ""
  local prefix = "You: "
  local text = line
  if vim.startswith(line, prefix) then
    text = line:sub(#prefix + 1)
  end
  if text:match("^%s*$") then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  lines[#lines] = "You: " .. text
  table.insert(lines, "AI: ")
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  state.assistant_start = #lines
  state.streaming = true

  vim.notify("Q: " .. sanitize_message(text))
  table.insert(state.messages, { role = "user", content = text })

  local payload_messages = {}
  if M.config.system_prompt and M.config.system_prompt ~= "" then
    table.insert(payload_messages, { role = "system", content = M.config.system_prompt })
  end
  for _, msg in ipairs(state.messages) do
    table.insert(payload_messages, msg)
  end

  request_stream(payload_messages, function(_, response)
    render_response(state, response)
  end, function(content, err)
    state.streaming = false
    if err then
      render_response(state, "Error: " .. sanitize_message(err))
      append_prompt(state)
      return
    end

    table.insert(state.messages, { role = "assistant", content = content })
    render_response(state, content)
    append_prompt(state)
  end)
end

function M.ask(message)
  local api_key = get_api_key()
  if not api_key then
    vim.notify("OpenRouter API key not set", vim.log.levels.ERROR)
    return
  end

  local state = ensure_chat()
  if not message or message == "" then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  lines[#lines] = "You: " .. message
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  send_current_input(state)
end

function M.open_chat()
  ensure_chat()
  local state = chat
  if state and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
    vim.cmd("startinsert")
  end
end

function M.setup(opts)
  if opts and type(opts) == "table" then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
end

return M
