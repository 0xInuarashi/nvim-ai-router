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

local function sanitize_message(text)
  if not text then
    return ""
  end
  return tostring(text):gsub("[%z\1-\31\127]", "")
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

local function parse_response(stdout)
  local ok, decoded = pcall(vim.fn.json_decode, stdout)
  if not ok or type(decoded) ~= "table" then
    return nil, "failed to parse response"
  end

  if decoded.error then
    if type(decoded.error) == "table" then
      local message = decoded.error.message or decoded.error.type or "request failed"
      return nil, message
    end
    return nil, tostring(decoded.error)
  end

  local choice = decoded.choices and decoded.choices[1]
  if not choice or not choice.message or not choice.message.content then
    return nil, "missing response content"
  end

  return choice.message.content, nil
end

local function build_curl_config(url, api_key)
  local lines = {
    "url = " .. url,
    "request = POST",
    "header = \"Authorization: Bearer " .. api_key .. "\"",
    "header = \"Content-Type: application/json\"",
    "silent",
    "show-error",
  }
  return lines
end

local function request(messages, cb)
  local api_key = get_api_key()
  if not api_key then
    vim.schedule(function()
      cb(nil, "missing OpenRouter API key")
    end)
    return
  end

  local url, url_err = validate_base_url(M.config.base_url)
  if not url then
    vim.schedule(function()
      cb(nil, url_err)
    end)
    return
  end

  local payload = {
    model = M.config.model,
    messages = messages,
  }

  local config_lines = build_curl_config(url, api_key)
  local config_path = vim.fn.tempname()
  vim.fn.writefile(config_lines, config_path)

  local payload_json = vim.fn.json_encode(payload)

  local cmd = {
    "curl",
    "--config",
    config_path,
    "--data-binary",
    "@-",
  }

  if vim.system then
    vim.system(cmd, { text = true, stdin = payload_json }, function(res)
      vim.schedule(function()
        pcall(vim.loop.fs_unlink, config_path)
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

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    stdin = "pipe",
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
        pcall(vim.loop.fs_unlink, config_path)
        if code ~= 0 then
          cb(nil, table.concat(stderr, "\n"))
          return
        end

        local content, err = parse_response(table.concat(stdout, "\n"))
        cb(content, err)
      end)
    end,
  })
  if job_id > 0 then
    vim.fn.chansend(job_id, payload_json)
    vim.fn.chanclose(job_id, "stdin")
  else
    pcall(vim.loop.fs_unlink, config_path)
  end
end

function M.ask(message)
  local api_key = get_api_key()
  if not api_key then
    vim.notify("OpenRouter API key not set", vim.log.levels.ERROR)
    return
  end

  vim.notify("Q: " .. sanitize_message(message))

  local messages = {}
  if M.config.system_prompt and M.config.system_prompt ~= "" then
    table.insert(messages, { role = "system", content = M.config.system_prompt })
  end
  table.insert(messages, { role = "user", content = message })
  request(messages, function(content, err)
    if err then
      vim.notify(sanitize_message(err), vim.log.levels.ERROR)
      return
    end

    vim.notify("A: " .. sanitize_message(content))
  end)
end

function M.setup(opts)
  if opts and type(opts) == "table" then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
end

return M
