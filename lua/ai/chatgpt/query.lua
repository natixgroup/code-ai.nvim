local curl = require('plenary.curl')
local query = {}

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

function query.buildMessages(system_instruction, project_context, prompt)
  local messages = {}
  table.insert(messages, { role = 'system', content = system_instruction })
  if #project_context > 0 then
    table.insert(messages, {role = 'user', content = "ChatGPT, I need your help on this project."})
    for _, context in ipairs(project_context) do
      table.insert(messages, {role = 'assistant', content = "What is the content of `" .. context.filename .. "` ?"})
      table.insert(messages, {role = 'user',  content = "The content of `" .. context.filename .. "` is :\n```" .. context.filecontent .. "\n```"})
    end
    table.insert(messages, {role = 'assistant', content = "Then what do you want me to do with all that information?"})
  end
  table.insert(messages, {role = 'user', content = prompt})
  return messages
end

function query.ask(instruction, project_context, prompt, opts, api_key)
  local prod_url = 'https://api.openai.com'
  -- local prod_url = 'https://eowloffrpvxwtqp.m.pipedream.net'
  local url_path = '/v1/chat/completions'
  curl.post( prod_url .. url_path,
    {
      headers = {
        [ 'Content-type' ] = 'application/json',
        [ 'Authorization' ] = 'Bearer ' .. api_key
      },
      body = vim.fn.json_encode(
          {
            model = 'gpt-4-turbo',
            messages = query.buildMessages(instruction, project_context, prompt),
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


