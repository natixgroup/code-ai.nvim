local gemini = require('ai.gemini.query')
local chatgpt = require('ai.chatgpt.query')

local default_prompts = {
  freeStyle = {
    command = 'AIIntroduceYourself',
    loading_tpl = 'Loading...',
    prompt_tpl = 'Say who you are, your version, and the currently used model',
    instruction_tpl = 'Act as a command line command that has been issued with the --help flag',
    result_tpl = '${output}',
    require_input = false,
  },
}

local M = {}
M.opts = {
  gemini_api_key = '',
  chatgpt_api_key = '',
  locale = 'en',
  alternate_locale = 'zh',
  result_popup_gets_focus = false,
}
M.prompts = default_prompts
local win_id

function M.log(message)
  local log_file = io.open("/tmp/aiconfig.log", "a")
  if not log_file then
    error("Could not open log file for writing.")
  end
  log_file:write(message .. "\n\n")
  log_file:close()
end

function M.findConfig()
  local path = vim.fn.getcwd() .. '/.aiconfig'
  -- Check if the file exists
  local file = io.open(path, "r")
  if file ~= nil then
    io.close(file)
    return path
  else
    return ""
  end
end

function M.listFilesFromConfig()
  local config = M.findConfig()
  if config == "" then
    return {}
  end
  local patterns = {}
  for line in io.lines(config) do
    table.insert(patterns, line)
  end
  local files = {}
  for _, pattern in ipairs(patterns) do
    for _, file in ipairs(vim.fn.glob(pattern, false, true)) do
      table.insert(files, file)
    end
  end
  return files
end

function M.readFilesFromAIConfig()
  if M.listFilesFromConfig() == {} then
    return {}
  end
  local files = M.listFilesFromConfig()
  local contents = {}
  for _, file in ipairs(files) do
    local f = io.open(file, "r")
    if f then
      local filename = file
      local filecontent = f:read("*all")
      table.insert(contents, {filename = filename, filecontent = filecontent})
      f:close()
    end
  end
  return contents
end


local function splitLines(input)
  local lines = {}
  local offset = 1
  while offset > 0 do
    local i = string.find(input, '\n', offset)
    if i == nil then
      table.insert(lines, string.sub(input, offset, -1))
      offset = 0
    else
      table.insert(lines, string.sub(input, offset, i - 1))
      offset = i + 1
    end
  end
  return lines
end

local function joinLines(lines)
  local result = ""
  for _, line in ipairs(lines) do
    result = result .. line .. "\n"
  end
  return result
end

local function isEmpty(text)
  return text == nil or text == ''
end

function M.hasLetters(text)
  return type(text) == 'string' and text:match('[a-zA-Z]') ~= nil
end


function M.getSelectedText(esc)
  if esc then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'n', false)
  end
  local vstart = vim.fn.getpos("'<")
  local vend = vim.fn.getpos("'>")
  -- If the selection has been made under VISUAL mode:
  local ok, lines = pcall(vim.api.nvim_buf_get_text, 0, vstart[2] - 1, vstart[3] - 1, vend[2] - 1, vend[3], {})
  if ok then
    return joinLines(lines)
  else
    -- If the selection has been made under VISUAL LINE mode:
    lines = vim.api.nvim_buf_get_lines(0, vstart[2] - 1, vend[2], false)
    return joinLines(lines)
  end
end

function M.close()
  if win_id == nil or win_id == vim.api.nvim_get_current_win() then
    return
  end
  pcall(vim.api.nvim_win_close, win_id, true)
  win_id = nil
end

function M.createPopup(initialContent, width, height)
  M.close()
  local bufnr = vim.api.nvim_create_buf(false, true)

  local update = function(content)
    if content == nil then
      content = ''
    end
    local lines = splitLines(content)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    vim.bo[bufnr].modifiable = false
  end

  win_id = vim.api.nvim_open_win(bufnr, false, {
    relative = 'cursor',
    border = 'single',
    title = 'code-ai.md',
    style = 'minimal',
    width = width,
    height = height,
    row = 1,
    col = 0,
  })
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  update(initialContent)
  if M.opts.result_popup_gets_focus then
    vim.api.nvim_set_current_win(win_id)
  end
  return update
end

function M.fill(tpl, args)
  if tpl == nil then
    tpl = ''
  else
    for key, value in pairs(args) do
      tpl = string.gsub(tpl, '%${' .. key .. '}', value)
    end
  end
  return tpl
end


function M.listScannedFiles()
  local analyzed_files_as_array = M.listFilesFromConfig()
  local analyzed_files_as_string = "\n\nThis is the list of analyzed files (list not part of the prompt)\n"
  for _, file in ipairs(analyzed_files_as_array) do
    analyzed_files_as_string = analyzed_files_as_string .. file .. "\n"
  end
  return analyzed_files_as_string
end

function M.handle(name, input)
  local def = M.prompts[name]
  local width = vim.fn.winwidth(0)
  local height = vim.fn.winheight(0)
  local args = {
    locale = M.opts.locale,
    alternate_locale = M.opts.alternate_locale,
    input = input,
    input_encoded = vim.fn.json_encode(input),
  }

  local update = M.createPopup(M.fill(def.loading_tpl .. M.listScannedFiles(), args), width - 12, height - 8)
  local prompt = M.fill(def.prompt_tpl, args)
  local instruction = M.fill(def.instruction_tpl, args)
  local project_context = M.readFilesFromAIConfig()

  local function handleResult(output, output_key)
    args[output_key] = output
    args.output = (args.gemini_output or '') .. (args.chatgpt_output or '')
    return M.fill(def.result_tpl or '${output}', args)
  end

  gemini.ask(
    instruction,
    project_context,
    prompt,
    {
      handleResult = function(gemini_output) return handleResult(gemini_output, 'gemini_output') end,
      callback = update
    },
    M.opts.gemini_api_key
  )

  chatgpt.ask(
    instruction,
    project_context,
    prompt,
    {
      handleResult = function(chatgpt_output) return handleResult(chatgpt_output, 'chatgpt_output') end,
      callback = update
    },
    M.opts.chatgpt_api_key
  )
end

function M.assign(table, other)
  for k, v in pairs(other) do
    table[k] = v
  end
  return table
end

function M.setup(opts)
  for k, v in pairs(opts) do
    if k == 'prompts' then
      M.prompts = {}
      M.assign(M.prompts, default_prompts)
      M.assign(M.prompts, v)
    elseif M.opts[k] ~= nil then
      M.opts[k] = v
    end
  end
  for k, v in pairs(M.prompts) do
    if v.command then
      vim.api.nvim_create_user_command(v.command, function(args)
        local text = args['args']
        if isEmpty(text) then
          text = M.getSelectedText(true)
        end
        if not v.require_input or M.hasLetters(text) then
          -- delayed so the popup won't be closed immediately
          vim.schedule(function()
            M.handle(k, text)
          end)
        end
      end, { range = true, nargs = '?' })
    end
  end
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
  callback = M.close,
})

vim.api.nvim_create_user_command(
  'AIListScannedFiles',
  function() M.handle('listScannedFiles', M.listScannedFiles()) end,
  {}
)

return M
