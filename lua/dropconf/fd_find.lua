--- Finds files using the 'fd' command-line tool.
---@param paths string[] the paths to search for lua files
---@param recurse dropconf.RecursionDepth how far from the base path(s) should the finder recurse down
---@return dropconf.FoundFiles found_files all the lua files found under each base path
local function _fd_find(paths, recurse)
  if #paths == 0 then
    return {}
  end

  local recurse_type = type(recurse)
  if recurse_type ~= type(0) and recurse_type ~= type(true) then
    vim.notify(("dropconf: expected recurse to be a 'number' or 'boolean', got: '%s'; defaulting to false"):format(recurse_type), vim.log.levels.WARN)
    recurse = false
    recurse_type = type(recurse)
  elseif recurse_type == type(0) then
    ---@cast recurse -boolean
    if recurse < 0 then
      vim.notify(("dropconf: recurse must be non-negative, got '%d'; defaulting to false"):format(recurse), vim.log.levels.WARN)
      recurse = false
      recurse_type = type(recurse)
    else
      recurse = math.floor(recurse)
    end
  end

  local function trim_slash(p)
    if p == '/' then
      return p
    end
    return (p:gsub('/+$', ''))
  end

  -- Normalize inputs to absolute and keep mapping abs -> list of original keys
  local abs_to_keys = {}
  local results = {}
  for _, p in ipairs(paths) do
    local abs = trim_slash(vim.fs.normalize(vim.fn.fnamemodify(p, ':p')))
    abs_to_keys[abs] = abs_to_keys[abs] or {}
    table.insert(abs_to_keys[abs], p)
    results[p] = {}
  end

  -- Unique absolute roots (preserve order)
  local absolute_paths = {}
  for abs, _ in pairs(abs_to_keys) do
    table.insert(absolute_paths, abs)
  end

  local check_paths = absolute_paths
  -- if recursing removing subpaths of existing path parameters to prevent duplicates
  if recurse then
    -- Sort to put smaller (more general) paths first
    table.sort(absolute_paths, function(a, b)
      return #a < #b
    end)
    check_paths = {}
    for _, abs_path in ipairs(absolute_paths) do
      local path_checked = false
      for _, check_path in ipairs(check_paths) do
        local normalized_check_path = (check_path:sub(-1) == '/') and '/' or (check_path .. '/')
        if vim.startswith(abs_path, normalized_check_path) then
          path_checked = true
          break
        end
      end
      if not path_checked then
        table.insert(check_paths, abs_path)
      end
    end
  end

  local fd_executable = vim.fn.executable 'fd' == 1 and 'fd' or 'fdfind'

  ---@type string[]
  local fd_cmd = {
    fd_executable,
    '-a',
    '-i',
    '-I',
    '-tf',
    '-td',
    '--print0',
    '^(?:[^.]+|.*\\.lua)$',
  }
  vim.list_extend(fd_cmd, check_paths)

  if type(recurse) == 'number' then
    -- Increment by one so always looking in descendant directories (by default a value of 1 is the current dir which is recurse = false)
    vim.list_extend(fd_cmd, { '--max-depth', tostring(recurse + 1) })
  elseif recurse == false then
    vim.list_extend(fd_cmd, { '--max-depth', '1' })
  end

  local file_paths = {}
  local res = vim.system(fd_cmd, { text = false }):wait()
  -- fd exit codes: 0 = matches, 1 = no matches, 2 = error
  if res.code == 0 or res.code == 1 then
    local out = res.stdout or ''
    if #out > 0 then
      file_paths = vim.split(out, '\0', { plain = true, trimempty = true })
    end
  else
    vim.notify(("dropconf: 'fd' exited %d: '%s'"):format(res.code, (res.stderr or '')), vim.log.levels.WARN)
  end

  -- Creating a fast look up table to check which path was given
  local starting_paths = {}
  for _, path in ipairs(absolute_paths) do
    starting_paths[path] = true
  end

  local function relpath(file, root)
    if not vim.startswith(file, root) then
      return file
    end
    local rel = file:sub(#root + 1)
    if rel:sub(1, 1) == '/' or rel:sub(1, 1) == '\\' then
      rel = rel:sub(2)
    end
    return rel
  end

  local seen_for_key = {}
  local function add_result_for_abs_root(abs_root, full)
    local rel = relpath(full, abs_root)
    for _, orig_key in ipairs(abs_to_keys[abs_root] or {}) do
      local seen = seen_for_key[orig_key]
      if not seen then
        seen = {}
        seen_for_key[orig_key] = seen
      end
      if not seen[rel] then
        table.insert(results[orig_key], rel)
        seen[rel] = true
      end
    end
  end

  for _, p in ipairs(file_paths) do
    local target = nil
    local st = vim.uv.fs_stat(p)
    if st and st.type == 'directory' then
      local initp = vim.fs.joinpath(p, 'init.lua')
      local st2 = vim.uv.fs_stat(initp)
      if st2 and st2.type == 'file' then
        target = initp
      end
    elseif st and st.type == 'file' then
      target = p
    end
    if target then
      local found_root = nil
      for dir in vim.fs.parents(target) do
        if starting_paths[dir] then
          found_root = dir
          break
        end
      end
      if found_root then
        add_result_for_abs_root(found_root, target)
      end
    end
  end

  return results
end

return _fd_find
