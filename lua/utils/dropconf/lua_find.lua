---@param paths string[] the paths to search for lua files
---@param recurse dropconf.RecursionDepth how far from the base path(s) should the finder recurse down
---@return dropconf.FoundFiles found_files all the lua files found under each base path
local function _lua_find(paths, recurse)
  if #paths == 0 then
    return {}
  end

  local uv = vim.uv or vim.loop

  -- Validate recurse
  local rt = type(recurse)
  if rt ~= 'number' and rt ~= 'boolean' then
    vim.notify(("dropconf: expected recurse to be number|boolean, got '%s'; defaulting false"):format(type(recurse)), vim.log.levels.WARN)
    recurse = false
    rt = 'boolean'
  elseif rt == 'number' then
    if recurse < 0 then
      vim.notify(('dropconf: recurse must be >= 0, got %d; defaulting false'):format(recurse), vim.log.levels.WARN)
      recurse = false
      rt = 'boolean'
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

  local function endswith_lua_case_insensitive(name)
    return name:lower():sub(-4) == '.lua'
  end

  local function is_hidden_name(name)
    return name:sub(1, 1) == '.'
  end

  -- Normalize inputs to absolute; map abs -> list of original keys
  local abs_to_keys = {}
  local results = {}
  for _, p in ipairs(paths) do
    local abs = trim_slash(vim.fs.normalize(vim.fn.fnamemodify(p, ':p')))
    abs_to_keys[abs] = abs_to_keys[abs] or {}
    table.insert(abs_to_keys[abs], p)
    results[p] = {}
  end

  -- Unique absolute roots
  local absolute_paths = {}
  for abs, _ in pairs(abs_to_keys) do
    table.insert(absolute_paths, abs)
  end

  local function is_recursing(r)
    if type(r) == 'boolean' then
      return r
    end
    return r > 0
  end

  -- Prune nested roots if recursing
  local check_paths = absolute_paths
  if is_recursing(recurse) then
    table.sort(absolute_paths, function(a, b)
      return #a < #b
    end)
    check_paths = {}
    for _, abs in ipairs(absolute_paths) do
      local covered = false
      for _, kept in ipairs(check_paths) do
        local prefix = kept == '/' and '/' or (kept .. '/')
        if vim.startswith(abs, prefix) then
          covered = true
          break
        end
      end
      if not covered then
        table.insert(check_paths, abs)
      end
    end
  end

  -- Depth model: "depth 1" lists immediate children of each root.
  local max_depth
  if rt == 'boolean' then
    max_depth = recurse and math.huge or 1
  else
    max_depth = recurse + 1
  end

  local seen_for_key = {}

  local function add_result_for_abs_root(abs_root, full)
    local rel = full:sub(#abs_root + 1)
    if rel:sub(1, 1) == '/' or rel:sub(1, 1) == '\\' then
      rel = rel:sub(2)
    end
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

  -- Walk helpers
  local function handle_immediate(root_abs)
    -- Depth 1: list immediate entries, add *.lua files,
    -- and also consider "<dir>/init.lua" without descending.
    for name, t in vim.fs.dir(root_abs) or function() end do
      if is_hidden_name(name) then
        goto continue
      end
      local full = vim.fs.joinpath(root_abs, name)
      if t == 'file' then
        if endswith_lua_case_insensitive(name) then
          add_result_for_abs_root(root_abs, full)
        end
      elseif t == 'directory' then
        local initp = vim.fs.joinpath(full, 'init.lua')
        local st = uv.fs_stat(initp)
        if st and st.type == 'file' then
          add_result_for_abs_root(root_abs, initp)
        end
      end
      ::continue::
    end
  end

  local function bfs_walk(root_abs)
    -- BFS so we can respect max_depth
    local q = { { dir = root_abs, depth = 1 } }
    local qi = 1
    while qi <= #q do
      local cur = q[qi]
      qi = qi + 1
      for name, t in vim.fs.dir(cur.dir) or function() end do
        if is_hidden_name(name) then
          goto continue
        end
        local full = vim.fs.joinpath(cur.dir, name)
        if t == 'file' then
          if endswith_lua_case_insensitive(name) then
            add_result_for_abs_root(root_abs, full)
          end
        elseif t == 'directory' then
          if cur.depth < max_depth then
            table.insert(q, { dir = full, depth = cur.depth + 1 })
          end
        end
        ::continue::
      end
    end
  end

  for _, root_abs in ipairs(check_paths) do
    if max_depth <= 1 then
      handle_immediate(root_abs)
    else
      bfs_walk(root_abs)
    end
  end

  return results
end

return _lua_find
