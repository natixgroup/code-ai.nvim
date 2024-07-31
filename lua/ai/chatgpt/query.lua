local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local json = require('ai.json')

local query = {}

function query.log(message)
  local log_file = io.open("/tmp/aiconfig.log", "a")
  if not log_file then
    error("Could not open log file for writing.")
  end
  log_file:write(message .. "\n\n")
  log_file:close()
end

function query.escapePercent(s)
  return string.gsub(s, "%%", "%%%%")
end

function query.formatResult(data)
  local result = '\n# This is ChatGPT answer\n\n'
  result = result .. data.choices[1].message.content .. '\n\n'
  return query.escapePercent(result)
end

function query.askCallback(res, opts)
  local result
  if res.status ~= 200 then
    if opts.handleError ~= nil then
      result = opts.handleError(res.status, res.body)
    else
      result = 'Error: ChatGPT API responded with the status ' .. tostring(res.status) .. '\n\n' .. res.body
    end
  else
    local data = vim.fn.json_decode(res.body)
    result = query.formatResult(data)
    if opts.handleResult ~= nil then
      result = opts.handleResult(result)
    end
  end
  opts.callback(result)
end

function query.askHeavy(instruction, prompt, opts, api_key, agent_host)
  local url = agent_host .. '/chatgpt'
  curl.get(url..'/clear', {callback = function(res) end})
  local project_context = aiconfig.listFilesFromConfig()
  local messages = {}
  table.insert(messages, {messages={ role = 'system', content = instruction }})
  if #project_context > 0 then
    table.insert(messages, {messages={role = 'user', content = "ChatGPT, I need your help on this project."}})
    for _, context in pairs(project_context) do
      table.insert(messages, {messages={role = 'assistant', content = "What is the content of `" .. context .. "` ?"}})
      table.insert(messages, {messages={role = 'user',  content = "The content of `" .. context .. "` is :\n```\n" .. aiconfig.contentOf(context) .. "\n```"}})
    end
    table.insert(messages, {messages={role = 'assistant', content = "Then what do you want me to do with all that information?"}})
  end
  table.insert(messages, {messages={role = 'user', content = prompt}})
  table.insert(messages, {model = 'gpt-4-turbo'})
  table.insert(messages, {temperature = 0.2})
  table.insert(messages, {top_p = 0.1})
  table.insert(messages, {})
  for i, message in ipairs(messages) do
    local body = json.encode(message)
    curl.post(url,
      {
        headers = {
          ['Content-type'] = 'application/json',
        },
        body = body,
        callback = function(res)
          if i == #messages then
            vim.schedule(function() query.askCallback(res, opts) end)
          end
        end
      })
  end

end
function query.ask(instruction, prompt, opts, api_key)
  local prod_url = 'https://api.openai.com'
  -- local prod_url = 'https://eowloffrpvxwtqp.m.pipedream.net'
  local url_path = '/v1/chat/completions'
  local project_context = aiconfig.listFilesFromConfig()

  curl.post(prod_url .. url_path,
    {
      headers = {
        ['Content-type'] = 'application/json',
        ['Authorization'] = 'Bearer ' .. api_key
      },
      body = json.encode(
        {
          model = 'gpt-4-turbo',
          messages = (function()
            local messages = {}
            table.insert(messages, { role = 'system', content = instruction })
            if #project_context > 0 then
              table.insert(messages, {role = 'user', content = "ChatGPT, I need your help on this project."})
              for _, context in pairs(project_context) do
                table.insert(messages, {role = 'assistant', content = "What is the content of `" .. context .. "` ?"})
                table.insert(messages, {role = 'user',  content = "The content of `" .. context .. "` is :\n```\n" .. aiconfig.contentOf(context) .. "\n```"})
              end
              table.insert(messages, {role = 'assistant', content = "Then what do you want me to do with all that information?"})
            end
            table.insert(messages, {role = 'user', content = prompt})
            return messages
          end)(),
          temperature = 0.2,
          top_p = 0.1
        }
      ),
      callback = function(res)
        vim.schedule(function() query.askCallback(res, opts) end)
      end
    })
end

return query


