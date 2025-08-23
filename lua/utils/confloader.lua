local M = {}

local config = {
  -- The active function used to find files. Set during initialization.
  finder = nil,
  -- A function to filter modules by their name (e.g., 'config.plugins.lualine').
  -- Default is to load all modules.
  filter_module = function(module_name)
    return true
  end,
  -- A function to filter files by their path.
  -- Default is to exclude files/dirs starting with '.' or '_'.
  filter_path = function(path)
    local basename = vim.fn.fnamemodify(path, ':t')
    return not vim.startswith(basename, '.') and not vim.startswith(basename, '_')
  end,
  recurse = true,
}

--- Finds files using the `fd` command-line tool.
---@param paths string[] an array of paths to recurse on
---@param recurse boolean|number whether the finder should recurse
local function _fd_find(paths, recurse)
  if #paths == 0 then
    return {}
  end

  local recurse_type = type(recurse)
  if recurse_type ~= type(0) and recurse_type ~= type(true) then
    vim.notify("Expected recurse to be a 'number' or 'boolean', got: '" .. recurse_type .. "'; defaulting to false", vim.log.levels.ERROR)
    recurse = false
    recurse_type = type(recurse)
  elseif recurse_type == type(0) then
    if recurse < 0 then
      vim.notify(("Recurse must be non-negative, got '%d'; defaulting to false"):format(recurse), vim.log.levels.ERROR)
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
  local seen_abs = {}
  for abs, _ in pairs(abs_to_keys) do
    table.insert(absolute_paths, abs)
    seen_abs[abs] = true
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
    local msg = ("fd exited %d: '%s'"):format(res.code, (res.stderr or ''):gsub('%s+$', ''))
    vim.notify(msg, vim.log.levels.WARN)
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

--- Pure-Lua finder with same input/output as _find_with_fd.
---@param paths string[]
---@param recurse boolean|number
---@return table<string, string[]>
local function _lua_find(paths, recurse)
  if #paths == 0 then
    return {}
  end

  local uv = vim.uv or vim.loop

  -- Validate recurse
  local rt = type(recurse)
  if rt ~= "number" and rt ~= "boolean" then
    vim.notify(
      "Expected recurse to be number|boolean, got " .. rt .. "; defaulting false",
      vim.log.levels.ERROR
    )
    recurse = false
    rt = "boolean"
  elseif rt == "number" then
    if recurse < 0 then
      vim.notify(
        ("Recurse must be >= 0, got %d; defaulting false"):format(recurse),
        vim.log.levels.ERROR
      )
      recurse = false
      rt = "boolean"
    else
      recurse = math.floor(recurse)
    end
  end

  local function trim_slash(p)
    if p == "/" then
      return p
    end
    return (p:gsub("/+$", ""))
  end

  local function endswith_lua_case_insensitive(name)
    return name:lower():sub(-4) == ".lua"
  end

  local function is_hidden_name(name)
    return name:sub(1, 1) == "."
  end

  -- Normalize inputs to absolute; map abs -> list of original keys
  local abs_to_keys = {}
  local results = {}
  for _, p in ipairs(paths) do
    local abs = trim_slash(vim.fs.normalize(vim.fn.fnamemodify(p, ":p")))
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
    if type(r) == "boolean" then
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
        local prefix = kept == "/" and "/" or (kept .. "/")
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
  if rt == "boolean" then
    max_depth = recurse and math.huge or 1
  else
    max_depth = recurse + 1
  end

  local seen_for_key = {}

  local function add_result_for_abs_root(abs_root, full)
    local rel = full:sub(#abs_root + 1)
    if rel:sub(1, 1) == "/" or rel:sub(1, 1) == "\\" then
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
      if t == "file" then
        if endswith_lua_case_insensitive(name) then
          add_result_for_abs_root(root_abs, full)
        end
      elseif t == "directory" then
        local initp = vim.fs.joinpath(full, "init.lua")
        local st = uv.fs_stat(initp)
        if st and st.type == "file" then
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
        if t == "file" then
          if endswith_lua_case_insensitive(name) then
            add_result_for_abs_root(root_abs, full)
          end
        elseif t == "directory" then
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

local function _internal_load(search_paths, options)
  local opts = vim.tbl_deep_extend('keep', options or {}, config)

  local dirs_to_load = {}
  local files_to_load = {}
  for _, path in ipairs(search_paths) do
    if vim.fn.isdirectory(path) == 1 then
      table.insert(dirs_to_load, path)
    else
      table.insert(files_to_load, path)
    end
  end

  local found_files_map = {}

  for _, file_path in ipairs(files_to_load) do
	  if vim.fn.filereadable(file_path) == 1 then
	  	local lua_pos = file_path:find('/lua/', 1, true)
		if lua_pos then
			local base_file_path = file_path:sub(1, lua_pos + 3)
			base_file_path = base_file_path:gsub('/+$', '')
			local rel_file_path = file_path:sub(lua_pos + 5)
			if rel_file_path ~= '' then
				found_files_map[base_file_path] = found_files_map[base_file_path] or {}
				table.insert(found_files_map[base_file_path], rel_file_path)
			end
		end
	  end
  end

  for base_path, files in pairs(opts.finder(dirs_to_load, opts.recurse)) do
	  found_files_map[base_path] = found_files_map[base_path] or {}
	vim.list_extend(found_files_map[base_path], files)
  end

  local modules_to_load = {}
  local seen_modules = {}
  for base_path, relative_files in pairs(found_files_map) do
    for _, rel_path in ipairs(relative_files) do
      local full_path = vim.fs.joinpath(base_path, rel_path)

      if not opts.filter_path(full_path) then
        goto continue
      end

      local module_name = rel_path:gsub('/', '.'):gsub('%.lua$', ''):gsub('%.init$', '')

      if not opts.filter_module(module_name) then
        goto continue
      end

      if not seen_modules[module_name] then
        table.insert(modules_to_load, { name = module_name, path = full_path })
        seen_modules[module_name] = true
      end

      ::continue::
    end
  end

  table.sort(modules_to_load, function(a, b)
    if vim.startswith(b.name, a.name .. '.') then
      return true
    end
    if vim.startswith(a.name, b.name .. '.') then
      return false
    end
    return a.name < b.name
  end)

  local results = {}
  for _, mod in ipairs(modules_to_load) do
    local ok, ret = pcall(dofile, mod.path)
    if not ok then
      vim.notify('Error loading module: ' .. mod.name .. '\n' .. tostring(ret), vim.log.levels.ERROR)
    elseif ret ~= nil then
      table.insert(results, ret)
    end
  end

  return results
end

---@param user_config table Configuration table with the following keys:
function M.setup(user_config)
  config = vim.tbl_deep_extend('keep', user_config or {}, config)
end

local function _parse_load_args(...)
  local items = {}
  local options = {}
  local nargs = select('#', ...)
  local args = { ... }

  if nargs > 0 and type(args[nargs]) == 'table' then
    options = table.remove(args, nargs)
  end

  for _, arg in ipairs(args) do
    if type(arg) == 'string' then
      table.insert(items, arg)
    elseif type(arg) == 'table' then
      vim.list_extend(items, arg)
    end
  end
  return items, options
end

---@vararg string|table A variable number of path strings or tables of path strings.
---@return table A flattened list of return values from the loaded modules.
function M.load_paths(...)
  local paths, options = _parse_load_args(...)
  return _internal_load(paths, options)
end

---@vararg string|table A variable number of module name strings or tables of strings.
---@return table file_results A flattened list of return values from the loaded modules.
function M.load_modules(...)
  local modules, options = _parse_load_args(...)

  local search_paths = {}
  local rtp = vim.api.nvim_list_runtime_paths()

  for _, mod_name in ipairs(modules) do
    local mod_path = mod_name:gsub('%.', '/')
    for _, path in ipairs(rtp) do
      local potential_dir_path = path .. '/lua/' .. mod_path
      if vim.fn.isdirectory(potential_dir_path) == 1 then
        table.insert(search_paths, potential_dir_path)
      end
      local potential_file_path = path .. '/lua/' .. mod_path .. '.lua'
      if vim.fn.filereadable(potential_file_path) == 1 then
        table.insert(search_paths, potential_file_path)
      end
    end
  end

  if #search_paths == 0 then
    return {}
  end
  return _internal_load(search_paths, options)
end

if vim.fn.executable 'fd' == 1 or vim.fn.executable 'fdfind' == 1 then
  config.finder = _fd_find
else
  config.finder = _lua_find
end

return M
