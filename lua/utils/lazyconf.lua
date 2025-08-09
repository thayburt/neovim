local M = {}

local uv = vim.uv or vim.loop

---@class PluginConfOptions
---@field config_dir string
---@field name_map fun(plugin: table|string): string|nil
---@field run_file fun(path: string, ctx: table)

---@type PluginConfOptions
local defaults = {
  config_dir = vim.fn.stdpath("config") .. "/lazyconf",

  -- Map a lazy.nvim plugin to a drop-in name (directory/file basename).
  -- By default uses lazy's plugin.name, falling back to repo dir basename.
  name_map = function(plugin)
    if type(plugin) == "table" and plugin.name then
      return plugin.name
    end
    if type(plugin) == "table" and plugin.dir then
      return vim.fs.basename(plugin.dir)
    end
    if type(plugin) == "string" then
      return plugin
    end
    return nil
  end,

  -- Called for each Lua file found. Override to change behavior.
  -- Default:
  --  - loads the chunk
  --  - runs it
  --  - if it returns a function, calls it with ctx
  run_file = function(path, ctx)
    local chunk, err = loadfile(path)
    if not chunk then
      vim.notify(
        ("lazyconf: loadfile failed: %s\n%s"):format(path, err),
        vim.log.levels.ERROR
      )
      return
    end
    local ok, ret = pcall(chunk)
    if not ok then
      vim.notify(
        ("lazyconf: error running %s\n%s"):format(path, ret),
        vim.log.levels.ERROR
      )
      return
    end
    if type(ret) == "function" then
      local ok2, err2 = pcall(ret, ctx)
      if not ok2 then
        vim.notify(
          ("lazyconf: error calling returned function from %s\n%s"):format(
            path,
            err2
          ),
          vim.log.levels.ERROR
        )
      end
    end
  end,
}

-- Internal state
local state = {
  processed = {}, -- [name]=true
  ---@type PluginConfOptions
  opts = vim.deepcopy(defaults), -- initialize so it's never nil for LuaLS
}

local function is_dir(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == 'directory'
end

local function is_file(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == 'file'
end

local function exists(path)
  return uv.fs_stat(path) ~= nil
end

local function join(a, b)
  return ('%s/%s'):format(a, b)
end

local function starts_hidden(name)
  local c = name:sub(1, 1)
  return c == '.' or c == '_'
end

local function is_lua_filename(name)
  return name:sub(-4) == '.lua'
end

local function base_without_ext(name)
  if is_lua_filename(name) then
    return name:sub(1, -5)
  end
  return name
end

-- Return entries (files and directories) mixed and sorted so that:
-- - Entries starting with . or _ are ignored
-- - Files must end with .lua (init.lua handled separately)
-- - For same base (e.g. 02.lua and 02/), file comes before directory
-- - Otherwise lexicographic by base name
local function mixed_entries(dir)
  local entries = {}

  for name, typ in vim.fs.dir(dir) do
    if not starts_hidden(name) then
      if typ == 'file' then
        if is_lua_filename(name) and name ~= 'init.lua' then
          table.insert(entries, { name = name, type = 'file' })
        end
      elseif typ == 'directory' then
        table.insert(entries, { name = name, type = 'directory' })
      end
      -- ignore other types
    end
  end

  table.sort(entries, function(a, b)
    local ab = base_without_ext(a.name)
    local bb = base_without_ext(b.name)
    if ab ~= bb then
      return ab < bb
    end
    if a.type ~= b.type then
      -- Prefer file over directory when same base
      return a.type == 'file'
    end
    -- Stable tiebreaker on name (rarely needed)
    return a.name < b.name
  end)

  return entries
end

-- Depth-first traversal with mixed file/dir order and per-directory init.lua:
-- In directory D:
--   1) run D/init.lua if present
--   2) iterate entries in mixed order (files and directories together):
--      - run file.lua
--      - recurse into subdirectory (which runs its init.lua first)
local function run_dir_recursive(dir, ctx, run_file)
  -- Tail-recursive DFS using an explicit frame stack; preserves ordering:
  -- init.lua, then mixed files/dirs (files before dirs with same base).
  local function step(frame, stack)
    if not frame.entered then
      local init_path = join(frame.dir, 'init.lua')
      if is_file(init_path) then
        run_file(init_path, ctx)
      end
      frame.entries = mixed_entries(frame.dir)
      frame.i = 1
      frame.entered = true
    end

    while frame.i <= #frame.entries and frame.entries[frame.i].type == 'file' do
      local e = frame.entries[frame.i]
      run_file(join(frame.dir, e.name), ctx)
      frame.i = frame.i + 1
    end

    if frame.i > #frame.entries then
      if #stack == 0 then
        return
      end
      local parent = table.remove(stack)
      return step(parent, stack)
    end

    local e = frame.entries[frame.i]
    frame.i = frame.i + 1
    stack[#stack + 1] = frame
    local child = { dir = join(frame.dir, e.name), entered = false }
    return step(child, stack)
  end

  return step({ dir = dir, entered = false }, {})
end

local function get_lazy_plugin(name)
  local ok, Config = pcall(require, 'lazy.core.config')
  if not ok then
    return nil
  end
  local plugin = Config.plugins and Config.plugins[name]
  if plugin then
    return plugin
  end
  -- Fallback: try linear search by dir basename
  for _, p in pairs(Config.plugins or {}) do
    if p.dir and vim.fs.basename(p.dir) == name then
      return p
    end
  end
  return nil
end

local function run_dropins_for(plugin_like)
  local opts = state.opts
  local name = opts.name_map(plugin_like)
  if not name then
    return
  end
  if state.processed[name] then
    return
  end

  local plugin = type(plugin_like) == 'string' and get_lazy_plugin(plugin_like) or plugin_like

  local ctx = {
    name = name,
    plugin = plugin or nil,
    dir = (plugin and plugin.dir) or nil,
  }

  local root = opts.config_dir
  local single = join(root, name .. '.lua')
  local dir = join(root, name)

  -- Execute single file first, then directory recursively with mixed order.
  if exists(single) then
    opts.run_file(single, ctx)
  end
  if is_dir(dir) then
    run_dir_recursive(dir, ctx, opts.run_file)
  end

  state.processed[name] = true
end

local function setup_autocmds()
  local aug = vim.api.nvim_create_augroup('LazyConfDropins', { clear = true })

  -- Primary: lazy.nvim emits "User LazyLoad" with event.data = plugin name
  vim.api.nvim_create_autocmd('User', {
    group = aug,
    pattern = 'LazyLoad',
    callback = function(ev)
      if ev and ev.data then
        -- Schedule to ensure we run after the plugin's own config
        vim.schedule(function()
          run_dropins_for(ev.data)
        end)
      end
    end,
  })

  -- Fallback for already-loaded plugins after startup
  vim.api.nvim_create_autocmd('User', {
    group = aug,
    pattern = 'VeryLazy',
    callback = function()
      local ok, Config = pcall(require, 'lazy.core.config')
      if ok and Config.plugins then
        for _, p in pairs(Config.plugins) do
          if p._ and p._.loaded then
            run_dropins_for(p)
          end
        end
      end
    end,
  })
end

function M.setup(opts)
  state.opts = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

  -- Ensure the lazyconf directory exists
  pcall(function()
    if not is_dir(state.opts.config_dir) then
      uv.fs_mkdir(state.opts.config_dir, 493) -- 0755
    end
  end)
  setup_autocmds()
end

return M
