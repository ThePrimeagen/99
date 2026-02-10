local M = {}

--- @class _99.Files.Config
--- @field enabled boolean?
--- @field max_file_size number?
--- @field max_files number?
--- @field exclude string[]?

--- @class _99.Files.File
--- @field path string  -- Relative path from project root
--- @field name string  -- Filename
--- @field absolute_path string  -- Full absolute path

local cache = {
  files = {},
  root = "",
}

local config = {
  enabled = true,
  max_file_size = 100 * 1024,
  max_files = 5000,
  exclude = {
    ".env",
    ".env.*",
    "node_modules",
    ".git",
    ".jj",
    "dist",
    "build",
    "*.log",
    ".DS_Store",
    "tmp",
    ".cursor",
  },
}

local base_exclude = vim.deepcopy(config.exclude)

--- @param pattern string
--- @return boolean
local function matches_exclude_pattern(pattern)
  for _, exclude_pattern in ipairs(config.exclude) do
    local glob_pattern = exclude_pattern:gsub("%.", "%%."):gsub("%*", ".*")

    if
      pattern:match(glob_pattern .. "$")
      or pattern:match("^" .. glob_pattern)
      or pattern:match("/" .. glob_pattern .. "/")
    then
      return true
    end
  end
  return false
end

--- @param path string
--- @param root string
--- @return string
local function get_relative_path(path, root)
  if path:sub(1, #root) == root then
    local rel = path:sub(#root + 1)
    if rel:sub(1, 1) == "/" then
      rel = rel:sub(2)
    end
    return rel
  end
  return path
end

--- @param root string
function M.set_project_root(root)
  cache.root = root
  cache.files = {}
end

--- @return string
function M.get_project_root()
  return cache.root
end

--- @return _99.Files.File[]
function M.discover_files()
  local root = cache.root
  if root == "" then
    return {}
  end

  local files = {}
  local count = 0

  local function scan_dir(dir)
    if count >= config.max_files then
      return
    end

    local handle = vim.uv.fs_scandir(dir)
    if not handle then
      return
    end

    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end

      local full_path = dir .. "/" .. name
      local rel_path = get_relative_path(full_path, root)

      if matches_exclude_pattern(name) or matches_exclude_pattern(rel_path) then
        goto continue
      end

      if type == "directory" then
        scan_dir(full_path)
      elseif type == "file" then
        table.insert(files, {
          path = rel_path,
          name = name,
          absolute_path = full_path,
        })
        count = count + 1

        if count >= config.max_files then
          break
        end
      end

      ::continue::
    end
  end

  scan_dir(root)

  table.sort(files, function(a, b)
    return a.path < b.path
  end)

  cache.files = files
  return files
end

--- @return _99.Files.File[]
function M.get_files()
  if #cache.files == 0 and cache.root ~= "" then
    return M.discover_files()
  end
  return cache.files
end

--- @param query string
--- @return _99.Files.File[]
function M.find_matches(query)
  local files = M.get_files()
  if not query or query == "" then
    return files
  end

  query = query:lower()
  local matches = {}

  for _, file in ipairs(files) do
    local searchable = (file.name .. " " .. file.path):lower()
    local match_pos = 1
    local matched = true
    for i = 1, #query do
      local char = query:sub(i, i)
      local found = searchable:find(char, match_pos, true)
      if not found then
        matched = false
        break
      end
      match_pos = found + 1
    end

    if matched then
      table.insert(matches, file)
    end
  end

  return matches
end

--- @param path string
--- @return string | nil
function M.read_file(path)
  local full_path = cache.root .. "/" .. path

  if path:sub(1, 1) == "/" then
    full_path = path
  end

  local stat = vim.uv.fs_stat(full_path)
  if not stat then
    return nil
  end

  if stat.size > config.max_file_size then
    return nil
  end

  local fd = vim.uv.fs_open(full_path, "r", 438)
  if not fd then
    return nil
  end

  local data = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)

  return data
end

--- @param path string
--- @return boolean
function M.is_project_file(path)
  local files = M.get_files()
  for _, file in ipairs(files) do
    if file.path == path or file.name == path then
      return true
    end
  end
  return false
end

--- @param path string
--- @return _99.Files.File | nil
function M.get_project_file(path)
  local files = M.get_files()
  for _, file in ipairs(files) do
    if file.path == path or file.name == path then
      return file
    end
  end
  return nil
end

--- @param opts _99.Files.Config?
--- @param rule_dirs string[]? Directories containing rules to exclude from file search
function M.setup(opts, rule_dirs)
  if opts then
    config.enabled = opts.enabled ~= false
    config.max_file_size = opts.max_file_size or config.max_file_size
    config.max_files = opts.max_files or config.max_files
    if opts.exclude then
      base_exclude = vim.deepcopy(opts.exclude)
    end
  end

  config.exclude = vim.deepcopy(base_exclude)

  if rule_dirs then
    local seen = {}
    for _, pattern in ipairs(config.exclude) do
      seen[pattern] = true
    end

    for _, dir in ipairs(rule_dirs) do
      local normalized = dir:gsub("/$", ""):gsub("^%./", "")

      if not seen[normalized] then
        table.insert(config.exclude, normalized)
        seen[normalized] = true
      end
    end
  end
end

--- @return _99.CompletionProvider
function M.completion_provider()
  return {
    trigger = "@",
    name = "files",
    get_items = function()
      local files = M.find_matches("")
      local items = {}
      for _, file in ipairs(files) do
        table.insert(items, {
          label = file.name,
          insertText = "@" .. file.path,
          filterText = "@" .. file.name .. " " .. file.path,
          kind = 17, -- LSP CompletionItemKind.Reference
          documentation = {
            kind = "markdown",
            value = "File: `" .. file.path .. "`",
          },
          detail = file.path,
        })
      end
      return items
    end,
    is_valid = function(token)
      return M.is_project_file(token)
    end,
    resolve = function(token)
      local file = M.get_project_file(token)
      if not file then
        return nil
      end
      local content = M.read_file(file.path)
      if not content then
        return nil
      end
      local ext = file.path:match("%.([^%.]+)$") or ""
      return string.format("```%s\n-- %s\n%s\n```", ext, file.path, content)
    end,
  }
end

return M
