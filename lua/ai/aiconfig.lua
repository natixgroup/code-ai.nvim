local aiconfig = {}

function aiconfig.findConfig()
  local path = vim.fn.getcwd() .. '/.aiconfig'
  local file = io.open(path, "r")
  if file ~= nil then
    io.close(file)
    return path
  else
    return ""
  end
end

function aiconfig.listFilesFromConfig()
  local config = aiconfig.findConfig()
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

function aiconfig.readFilesFromAIConfig()
  if aiconfig.listFilesFromConfig() == {} then
    return {}
  end
  local files = aiconfig.listFilesFromConfig()
  local contents = {}
  for _, file in ipairs(files) do
    local f = io.open(file, "r")
    if f then
      local filename = file
      local filecontent = f:read("*all")
      table.insert(contents, {filename = filename, filecontent = ''})
      f:close()
    end
  end
  return contents
end

function aiconfig.listScannedFiles()
  local analyzed_files_as_array = aiconfig.listFilesFromConfig()
  local analyzed_files_as_string = "\n# This is the list of analyzed files (list not part of the prompt)\n"
  for _, file in ipairs(analyzed_files_as_array) do
    local full_path = vim.fn.getcwd() .. '/' .. file
    local stat = vim.loop.fs_stat(full_path)
    local size = stat and stat.size or "unknown"
    local size_str = size .. " B"
    if size > 1024 then
      size_str = string.format("%.2f KB", size / 1024)
    end
    if size > 1024 * 1024 then
      size_str = string.format("%.2f MB", size / (1024 * 1024))
    end
    analyzed_files_as_string = analyzed_files_as_string .. "- " .. file .. " (Size: " .. size_str .. ")\n"
  end
  return analyzed_files_as_string
end

return aiconfig
