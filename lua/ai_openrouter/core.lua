-- AI OpenRouter Core Module
-- Main logic for the AI OpenRouter plugin

local M = {}

-- Configuration
M.config = {
    api_key = vim.env.OPENROUTER_API_KEY or '',
    model = 'openrouter/auto',
    temperature = 0.7,
    base_url = 'https://openrouter.ai/api/v1',
    window_width = 0.8,
    window_height = 0.9,
}

-- State
M.state = {
    chat_history = {},
    window_id = nil,
    buffer_id = nil,
    input_buffer_id = nil,
    input_window_id = nil,
}

-- Initialize configuration from global settings
local function init_config()
    M.config.api_key = vim.g.ai_openrouter_api_key or ''
    if vim.g.ai_openrouter_model and vim.g.ai_openrouter_model ~= '' then
        M.config.model = vim.g.ai_openrouter_model
    end
    if vim.g.ai_openrouter_temperature and vim.g.ai_openrouter_temperature ~= '' then
        M.config.temperature = vim.g.ai_openrouter_temperature
    end
end

-- Make API request to OpenRouter
local function call_openrouter(messages)
    if M.config.api_key == '' then
        return nil, 'Error: OPENROUTER_API_KEY not set'
    end

    local curl_cmd = {
        'curl',
        '-s',
        '-X', 'POST',
        M.config.base_url .. '/chat/completions',
        '-H', 'Content-Type: application/json',
        '-H', 'Authorization: Bearer ' .. M.config.api_key,
        '-d', vim.fn.json_encode({
            model = M.config.model,
            messages = messages,
            temperature = M.config.temperature,
            max_tokens = 2000,
        })
    }

    local handle = io.popen(table.concat(curl_cmd, ' '))
    if not handle then
        return nil, 'Error: Failed to execute curl'
    end

    local response = handle:read('*a')
    handle:close()

    -- Parse JSON response
    local ok, json = pcall(vim.fn.json_decode, response)
    if not ok then
        return nil, 'Error: Failed to parse API response'
    end

    -- Check for errors in response
    if json.error then
        return nil, 'Error: ' .. (json.error.message or 'Unknown API error')
    end

    if not json.choices or not json.choices[1] then
        return nil, 'Error: Invalid API response format'
    end

    return json.choices[1].message.content
end

-- Word wrap text to a certain width
local function wrap_text(text, width)
    local lines = {}
    local current_line = ''

    for word in text:gmatch('%S+') do
        if #current_line + #word + 1 <= width then
            if current_line == '' then
                current_line = word
            else
                current_line = current_line .. ' ' .. word
            end
        else
            if current_line ~= '' then
                table.insert(lines, current_line)
            end
            current_line = word
        end
    end

    if current_line ~= '' then
        table.insert(lines, current_line)
    end

    return lines
end

-- Update chat display
local function update_chat_display()
    if not vim.api.nvim_buf_is_valid(M.state.buffer_id) then
        return
    end

    local lines = {}
    table.insert(lines, '╔════════════════════════════════════════════════════════╗')
    table.insert(lines, '║                      AI Chat (OpenRouter)              ║')
    table.insert(lines, '╚════════════════════════════════════════════════════════╝')
    table.insert(lines, '')

    for _, msg in ipairs(M.state.chat_history) do
        if msg.role == 'user' then
            table.insert(lines, '┌─ You:')
            table.insert(lines, '│ ' .. msg.content)
            table.insert(lines, '└' .. string.rep('─', 50))
        else
            table.insert(lines, '┌─ AI:')
            -- Word wrap long responses
            local wrapped = wrap_text(msg.content, 48)
            for _, line in ipairs(wrapped) do
                table.insert(lines, '│ ' .. line)
            end
            table.insert(lines, '└' .. string.rep('─', 50))
        end
        table.insert(lines, '')
    end

    vim.api.nvim_buf_set_lines(M.state.buffer_id, 0, -1, false, lines)
    -- Scroll to bottom
    vim.api.nvim_win_set_cursor(M.state.window_id, { #lines, 0 })
end

-- Setup keymaps for input buffer
local function setup_keymaps()
    vim.api.nvim_buf_set_keymap(M.state.input_buffer_id, 'n', 'q', ':lua require("ai_openrouter").close_chat()<CR>', {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(M.state.input_buffer_id, 'n', '<CR>', ':lua require("ai_openrouter").send_message()<CR>', {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(M.state.input_buffer_id, 'i', '<C-c>', '<Esc>:lua require("ai_openrouter").close_chat()<CR>', {
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(M.state.input_buffer_id, 'i', '<C-CR>', '<Esc>:lua require("ai_openrouter").send_message()<CR>', {
        noremap = true,
        silent = true,
    })
end

-- Create chat window and buffers
local function create_windows()
    -- Create main chat buffer
    M.state.buffer_id = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(M.state.buffer_id, 'modifiable', true)
    vim.api.nvim_buf_set_option(M.state.buffer_id, 'filetype', 'ai_openrouter')

    -- Create input buffer
    M.state.input_buffer_id = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(M.state.input_buffer_id, 'modifiable', true)

    -- Calculate window dimensions
    local width = math.floor(vim.o.columns * M.config.window_width)
    local height = math.floor(vim.o.lines * M.config.window_height)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create main chat window
    M.state.window_id = vim.api.nvim_open_win(M.state.buffer_id, false, {
        relative = 'editor',
        width = width,
        height = height - 4,
        row = row,
        col = col,
        border = 'rounded',
        style = 'minimal',
    })

    -- Create input window
    M.state.input_window_id = vim.api.nvim_open_win(M.state.input_buffer_id, true, {
        relative = 'editor',
        width = width,
        height = 3,
        row = row + height - 4,
        col = col,
        border = 'rounded',
        style = 'minimal',
    })

    setup_keymaps()

    -- Insert mode in input window
    vim.cmd('startinsert')

    update_chat_display()
end

-- Send a message to the AI
function M.send_message()
    local input_lines = vim.api.nvim_buf_get_lines(M.state.input_buffer_id, 0, -1, false)
    local user_input = table.concat(input_lines, '\n'):gsub('^%s+|%s+$', '')

    if user_input == '' then
        return
    end

    -- Add user message to history
    table.insert(M.state.chat_history, {
        role = 'user',
        content = user_input,
    })

    -- Clear input buffer
    vim.api.nvim_buf_set_lines(M.state.input_buffer_id, 0, -1, false, { '' })

    -- Show "thinking" indicator
    update_chat_display()
    vim.api.nvim_buf_set_lines(M.state.buffer_id, -1, -1, false, { '┌─ AI:', '│ Thinking...', '└' .. string.rep('─', 50), '' })
    vim.api.nvim_win_set_cursor(M.state.window_id, { vim.api.nvim_buf_line_count(M.state.buffer_id), 0 })

    -- Call API
    local response, err = call_openrouter(M.state.chat_history)

    if not response then
        vim.api.nvim_buf_set_lines(M.state.buffer_id, -2, -1, false, { '│ Error: ' .. err, '└' .. string.rep('─', 50), '' })
        vim.api.nvim_win_set_cursor(M.state.window_id, { vim.api.nvim_buf_line_count(M.state.buffer_id), 0 })
        return
    end

    -- Add AI response to history
    table.insert(M.state.chat_history, {
        role = 'assistant',
        content = response,
    })

    update_chat_display()
    vim.cmd('startinsert')
end

-- Close chat window
function M.close_chat()
    if M.state.window_id and vim.api.nvim_win_is_valid(M.state.window_id) then
        vim.api.nvim_win_close(M.state.window_id, true)
    end
    if M.state.input_window_id and vim.api.nvim_win_is_valid(M.state.input_window_id) then
        vim.api.nvim_win_close(M.state.input_window_id, true)
    end
    M.state.window_id = nil
    M.state.input_window_id = nil
end

-- Clear chat history
function M.clear_history()
    M.state.chat_history = {}
    if M.state.buffer_id and vim.api.nvim_buf_is_valid(M.state.buffer_id) then
        update_chat_display()
    end
end

-- Open chat window
function M.open_chat()
    init_config()
    create_windows()
end

return M
