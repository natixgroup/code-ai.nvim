local curl = require('plenary.curl')
local aiconfig = require('ai.aiconfig')
local query = {}

function query.escapePercent(s)
  return string.gsub(s, "%%", "%%%%")
end

function query.formatResult(data)
  local result = ''
  local candidates_number = #data['candidates']
  if candidates_number == 1 then
    if data['candidates'][1]['content'] == nil then
      result = '\n#Gemini error\n\nGemini stopped with the reason: ' .. data['candidates'][1]['finishReason'] .. '\n'
      return result
    else
      result = '\n# This is Gemini answer\n\n'
      result = result .. query.escapePercent(data['candidates'][1]['content']['parts'][1]['text']) .. '\n'
    end
  else
    result = '# There are ' .. candidates_number .. ' Gemini candidates\n'
    for i = 1, candidates_number do
      result = result .. '## Gemini Candidate number ' .. i .. '\n'
      result = result .. data['candidates'][i]['content']['parts'][1]['text'] .. '\n'
    end
  end
  return result
end

function query.askCallback(res, opts)
  local result
  if res.status ~= 200 then
    if opts.handleError ~= nil then
      result = opts.handleError(res.status, res.body)
    else
      result = 'Error: Gemini API responded with the status ' .. tostring(res.status) .. '\n\n' .. res.body
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

function query.ask(instruction, prompt, opts, api_key)
  local prod_url = 'https://generativelanguage.googleapis.com'
  -- local prod_url = 'https://eowloffrpvxwtqp.m.pipedream.net'
  local prod_path = '/v1beta/models/gemini-1.5-pro-latest:generateContent'
  local project_context = aiconfig.listFilesFromConfig()
  curl.post(prod_url .. prod_path,
    {
      headers = {
        ['Content-type'] = 'application/json',
        ['x-goog-api-key'] = api_key
      },
      body = vim.fn.json_encode(
        {
          system_instruction = {parts = {text = instruction}},
          contents = (function()
            local contents = {}
            if #project_context > 0 then
              table.insert(contents, {role = 'user', parts = {{text = "Gemini, I need your help on this project."}}})
              for _, context in pairs(project_context) do
                table.insert(contents, {role = 'model', parts = {{text = "What is the content of `" .. context .. "` ?"}}})
                -- table.insert(contents, {role = 'user', parts = {{text = "The content of `" .. context .. "` is :\n```" .. aiconfig.returnContentsOf(context) .. "\n```"}}})
                table.insert(contents, {role = 'user', parts = {{text = "The content of `" .. context .. "` is :\n```" }}})
              end
              table.insert(contents, {role = 'model', parts = {{text = "Then what do you want me to do with all that information?"}}})
            end
            table.insert(contents, {role = 'user', parts = {{text = prompt}}})
            return contents
          end)(),
          safetySettings = {
            { category = 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold = 'BLOCK_NONE' },
            { category = 'HARM_CATEGORY_HATE_SPEECH',       threshold = 'BLOCK_NONE' },
            { category = 'HARM_CATEGORY_HARASSMENT',        threshold = 'BLOCK_NONE' },
            { category = 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold = 'BLOCK_NONE' }
          },
          generationConfig = {
            temperature = 0.2,
            topP = 0.5
          }
        }),
      callback = function(res)
         vim.schedule(function() query.askCallback(res, opts) end)
      end
    })
end

return query
