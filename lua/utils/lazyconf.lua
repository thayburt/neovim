---@diagnostic disable: need-check-nil
-- utils/lazyconf.lua
local M = {}

local uv = vim.uv or vim.loop

---@alias LazyConfReloadMode "none" | "all" | "changed"

---@class LazyConfOptions
---@field module_prefix string
---@field name_map fun(plugin: table|string): string|nil
---@field dropconf_opts? table
---@field ignore_hidden boolean
---@field reload_on_update LazyConfReloadMode
local defaults = {
  module_prefix = 'lazyconf',

  name_map = function(plugin)
    if type(plugin) == 'table' and plugin.name then
      return plugin.name
    end
    if type(plugin) == 'table' and plugin.dir then
      return vim.fs.basename(plugin.dir)
    end
    if type(plugin) == 'string' then
      return plugin
    end
    return nil
  end,

  dropconf_opts = {
    recurse = true,
  },

  ignore_hidden = true,
  reload_on_update = 'changed',
}

-- Internal state
local state = {
  processed = {}, -- [plugin_name]=true (original lazy name)
  hooks = {}, -- [plugin_name]={ unload=fun[]; update=fun[] }
  dir_mtime = {}, -- [plugin_name]=number (ns)
  ---@type LazyConfOptions
  opts = vim.deepcopy(defaults),
}

-- Utils

local function join_mod(a, b)
  if not a or a == '' then
    return b
  end
  return ('%s.%s'):format(a, b)
end

-- Only used for Lua module paths. We keep the original name for state/events.
local function sanitize_for_module(name)
  return (name or ''):gsub('%.', '-')
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
  for _, p in pairs(Config.plugins or {}) do
    if p.dir and vim.fs.basename(p.dir) == name then
      return p
    end
  end
  return nil
end

local function get_dir_mtime_ns(path)
  local st = path and uv.fs_stat(path) or nil
  if not st or not st.mtime then
    return 0
  end
  local m = st.mtime
  if type(m) == 'number' then
    return math.floor(m * 1e9)
  elseif type(m) == 'table' then
    return (m.sec or 0) * 1e9 + (m.nsec or 0)
  end
  return 0
end

local function emit_event(pattern, data)
  pcall(vim.api.nvim_exec_autocmds, 'User', {
    pattern = pattern,
    modeline = false,
    data = data,
  })
end

-- Build a filter_path for dropconf that:
-- - excludes hidden segments if enabled
-- - optionally composes with a user-provided predicate
local function build_filter_path(module_name)
  local ignore_hidden = state.opts.ignore_hidden
  local user_fp = state.opts.dropconf_opts and state.opts.dropconf_opts.filter_path or nil

  local function hidden_ok(path)
    if not ignore_hidden then
      return true
    end
    local p = (path or ''):gsub('\\', '/')
    for seg in p:gmatch '[^/]+' do
      local c = seg:sub(1, 1)
      if c == '.' or c == '_' then
        return false
      end
    end
    return true
  end

  if type(user_fp) ~= 'function' then
    return hidden_ok
  end

  return function(path)
    if not hidden_ok(path) then
      return false
    end
    local ok, res = pcall(user_fp, path)
    if not ok then
      vim.notify(('lazyconf: filter_path error for %s: %s'):format(module_name, tostring(res)), vim.log.levels.WARN)
      return false
    end
    return not not res
  end
end

-- Hooks

local function run_unload_hooks(name)
  local h = state.hooks[name]
  if not h or not h.unload then
    return
  end
  for _, fn in ipairs(h.unload) do
    local ok, err = pcall(fn)
    if not ok then
      vim.notify(('lazyconf: on_unload for %s failed: %s'):format(name, tostring(err)), vim.log.levels.ERROR)
    end
  end
end

local function run_update_hooks(name)
  local h = state.hooks[name]
  if not h or not h.update then
    return
  end
  for _, fn in ipairs(h.update) do
    local ok, err = pcall(fn)
    if not ok then
      vim.notify(('lazyconf: on_update for %s failed: %s'):format(name, tostring(err)), vim.log.levels.ERROR)
    end
  end
end

local function clear_plugin_state(name)
  state.processed[name] = nil
  state.hooks[name] = nil
  state.dir_mtime[name] = nil
end

-- Load the plugin's drop-in configs using utils.dropconf
local function load_plugin_config(raw_name, plugin)
  local module_name = sanitize_for_module(raw_name)
  local module_str = join_mod(state.opts.module_prefix, module_name)

  local cl_ok, dropconf = pcall(require, 'utils.dropconf')
  if not cl_ok then
    vim.notify('lazyconf: failed to require utils.dropconf', vim.log.levels.ERROR)
    return
  end

  local cl_opts = vim.tbl_extend('force', {}, state.opts.dropconf_opts or {})
  cl_opts.filter_path = build_filter_path(module_str)

  local ok_call, returned = pcall(function()
    return dropconf.load_modules(module_str, cl_opts)
  end)

  if not ok_call then
    vim.notify(('lazyconf: dropconf error for %s\n%s'):format(module_str, tostring(returned)), vim.log.levels.ERROR)
    return
  end

  local unload_hooks, update_hooks = {}, {}
  for _, val in ipairs(returned or {}) do
    if type(val) == 'function' then
      table.insert(unload_hooks, val)
    elseif type(val) == 'table' then
      local u = val.on_unload or val.unload
      if type(u) == 'function' then
        table.insert(unload_hooks, u)
      end
      local up = val.on_update or val.update
      if type(up) == 'function' then
        table.insert(update_hooks, up)
      end
    end
  end

  state.hooks[raw_name] = { unload = unload_hooks, update = update_hooks }

  local dir = (plugin and plugin.dir) or nil
  state.dir_mtime[raw_name] = get_dir_mtime_ns(dir)
end

local function run_dropins_for(plugin_like)
  local opts = state.opts
  if not opts then
    return
  end

  local raw_name = opts.name_map(plugin_like)
  if not raw_name or raw_name == '' then
    return
  end
  if state.processed[raw_name] then
    return
  end

  local plugin = type(plugin_like) == 'string' and get_lazy_plugin(plugin_like) or plugin_like

  load_plugin_config(raw_name, plugin)
  state.processed[raw_name] = true
end

-- Public API

function M.reload(plugin_like)
  if not state.opts then
    return false
  end
  local raw_name = state.opts.name_map(plugin_like)
  if not raw_name then
    return false
  end
  if state.processed[raw_name] then
    run_unload_hooks(raw_name)
    emit_event('LazyConfUnload', raw_name)
    clear_plugin_state(raw_name)
  end
  run_dropins_for(plugin_like)
  return true
end

function M.reload_all()
  local ok, Config = pcall(require, 'lazy.core.config')
  if not ok or not Config.plugins then
    return
  end

  for name, processed in pairs(state.processed) do
    if processed then
      run_unload_hooks(name)
      emit_event('LazyConfUnload', name)
    end
  end

  state.processed = {}
  state.hooks = {}
  state.dir_mtime = {}

  for _, p in pairs(Config.plugins) do
    if p._ and p._.loaded then
      run_dropins_for(p)
    end
  end
end

function M.cleanup(plugin_like)
  if not state.opts then
    return false
  end
  local raw_name = state.opts.name_map(plugin_like)
  if not raw_name or not state.processed[raw_name] then
    return false
  end
  run_unload_hooks(raw_name)
  emit_event('LazyConfUnload', raw_name)
  clear_plugin_state(raw_name)
  return true
end

-- Autocmds

local function handle_unload_event(ev)
  if ev and ev.data then
    M.cleanup(ev.data)
    return
  end

  local ok, Config = pcall(require, 'lazy.core.config')
  if not ok then
    return
  end
  for name, processed in pairs(state.processed) do
    if processed then
      local p = Config.plugins and Config.plugins[name] or nil
      local loaded = p and p._ and p._.loaded or false
      local exists = p and p.dir and uv.fs_stat(p.dir) ~= nil or false
      if not loaded or not exists then
        M.cleanup(name)
      end
    end
  end
end

local function handle_update_event()
  local mode = state.opts.reload_on_update
  if mode == 'none' then
    return
  end

  local ok, Config = pcall(require, 'lazy.core.config')
  if not ok or not Config.plugins then
    return
  end

  for name, processed in pairs(state.processed) do
    if processed then
      local p = Config.plugins[name]
      if p and p.dir then
        local now = get_dir_mtime_ns(p.dir)
        local prev = state.dir_mtime[name] or 0
        local should = (mode == 'all') or (now > 0 and now ~= prev)
        if should then
          M.reload(name)
          run_update_hooks(name)
          emit_event('LazyConfUpdate', name)
        end
      end
    end
  end
end

local function setup_autocmds()
  local aug = vim.api.nvim_create_augroup('LazyConfDropins', { clear = true })

  vim.api.nvim_create_autocmd('User', {
    group = aug,
    pattern = 'LazyLoad',
    callback = function(ev)
      if ev and ev.data then
        vim.schedule(function()
          run_dropins_for(ev.data)
        end)
      end
    end,
  })

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

  vim.api.nvim_create_autocmd('User', {
    group = aug,
    pattern = { 'LazyUnload', 'LazyClean' },
    callback = function(ev)
      handle_unload_event(ev)
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    group = aug,
    pattern = { 'LazyUpdate', 'LazySync' },
    callback = function()
      handle_update_event()
    end,
  })
end

function M.setup(opts)
  state.opts = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  state.opts.dropconf_opts = state.opts.dropconf_opts or {}
  if state.opts.dropconf_opts.recurse == nil then
    state.opts.dropconf_opts.recurse = true
  end
  setup_autocmds()
end

return M
