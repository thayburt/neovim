-- lua/utils/dropins.lua
-- "Drop-ins" loader: aggregate modules across runtimepath and prefer user config.
-- Behavior:
-- - If the given module name points to a directory (lua/<mod>/), we will:
--   - Load that directory's init.lua first if present, then every other .lua in
--     the directory; if recursive = true, recursively apply the same rule to
--     subdirectories (each subdir's init.lua first, then its files, then its
--     children).
-- - If no directory exists but a file exists (lua/<mod>.lua), load only that
--   single file (highest priority across RTP).
-- - Across RTP, the user config (stdpath("config")) wins over others; otherwise
--   RTP order decides.
-- - All requires are done by module name (not by path) for proper caching.
--
-- Setup:
--   require("utils.dropins").setup({
--     recursive = true,
--     silent = false,
--     predicate = function(mod, path) return true end,
--   })
--
-- Use:
--   local dropins = require("utils.dropins")
--   dropins.load_module("config.dropins")                -- directory mode
--   dropins.load_module("config.dropins", { recursive = true })
--   dropins.load_module("config.dropins.alpha")          -- single file if exists

---@alias DropinLoaderPredicate fun(modname: string, path: string): boolean

---@class DropinLoaderOptions
---@field recursive? boolean Load subdirectories (default: false)
---@field silent? boolean Suppress notifications (default: false)
---@field predicate? DropinLoaderPredicate Filter which modules to load

local M = {}

-- Global defaults (user-overridable via setup)
---@type DropinLoaderOptions
local defaults = {
  recursive = false,
  silent = false,
  predicate = nil,
}

---Override global defaults.
---@param opts? DropinLoaderOptions
function M.setup(opts)
  if not opts then
    return
  end
  defaults = vim.tbl_deep_extend("force", defaults, opts)
end

---@param mod string
---@return string lua_rel_dir e.g. "lua/config/dropins"
local function mod_to_rel_dir(mod)
  return ("lua/%s"):format(mod:gsub("%.", "/"))
end

---@param mod string
---@return string lua_rel_file e.g. "lua/config/dropins.lua"
local function mod_to_rel_file(mod)
  return ("lua/%s.lua"):format(mod:gsub("%.", "/"))
end

---List runtime paths with their index to preserve RTP order.
---@return {rtp: string, idx: integer}[]
local function list_rtp_with_index()
  local out = {}
  for i, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
    table.insert(out, { rtp = rtp, idx = i })
  end
  return out
end

---Compute priority: lower is better. User config wins, then RTP order.
---@param rtp string
---@param idx integer
---@return integer
local function rtp_priority(rtp, idx)
  local cfg = vim.fn.stdpath("config")
  local is_user = type(cfg) == "string" and #cfg > 0 and rtp:sub(1, #cfg) == cfg
  if is_user then
    -- Ensure user entries are strictly before any non-user.
    return idx
  else
    return 100000 + idx
  end
end

---@param path string
---@return boolean is_dir
local function is_dir(path)
  local st = vim.uv.fs_stat(path)
  return st and st.type == "directory" or false
end

---@param path string
---@return boolean is_file
local function is_file(path)
  local st = vim.uv.fs_stat(path)
  return st and st.type == "file" or false
end

---Find all directories matching the module directory across RTP.
---@param mod string
---@return {rtp: string, idx: integer, dir: string}[]
local function find_all_dirs(mod)
  local rel_dir = mod_to_rel_dir(mod)
  local out = {}
  for _, ent in ipairs(list_rtp_with_index()) do
    local dir = vim.fs.joinpath(ent.rtp, rel_dir)
    if is_dir(dir) then
      table.insert(out, { rtp = ent.rtp, idx = ent.idx, dir = dir })
    end
  end
  return out
end

---Find the best single-file candidate for a module, if any.
---@param mod string
---@return {mod: string, path: string, priority: integer}|nil
local function best_single_file_candidate(mod)
  local rel_file = mod_to_rel_file(mod)
  local best = nil
  for _, ent in ipairs(list_rtp_with_index()) do
    local f = vim.fs.joinpath(ent.rtp, rel_file)
    if is_file(f) then
      local prio = rtp_priority(ent.rtp, ent.idx)
      if not best or prio < best.priority then
        best = { mod = mod, path = f, priority = prio }
      end
    end
  end
  return best
end

---Require with protection and optional notification.
---@param mod string
---@param silent boolean
---@return boolean
local function safe_require(mod, silent)
  local ok, err = pcall(require, mod)
  if not ok and not silent then
    vim.notify(
      ("dropins: error requiring %q:\n%s"):format(mod, err),
      vim.log.levels.ERROR
    )
  end
  return ok
end

-- A merged tree of drop-in candidates across RTP, deduped by priority
-- Node represents a module directory prefix.
---@class DropinNode
---@field name string Module prefix (e.g., "config.dropins")
---@field init? { mod: string, path: string, priority: integer }
---@field files table<string, { mod: string, path: string, priority: integer }>
---@field children table<string, DropinNode>

---Create a new node.
---@param name string
---@return DropinNode
local function new_node(name)
  return { name = name, init = nil, files = {}, children = {} }
end

---Merge a candidate into a slot if it has higher priority (lower number).
---@param slot table|nil
---@param cand {mod: string, path: string, priority: integer}
---@return table The winning candidate
local function choose_best(slot, cand)
  if not slot or cand.priority < slot.priority then
    return cand
  end
  return slot
end

---@param pred DropinLoaderPredicate|nil
---@param mod string
---@param path string
local function should_load(pred, mod, path)
  if pred == nil then
    return true
  end
  return pred(mod, path)
end

---Scan a directory into the node tree, merging by priority.
---@param node DropinNode
---@param dir string
---@param priority integer
---@param recursive boolean
---@param pred DropinLoaderPredicate|nil
local function scan_dir(node, dir, priority, recursive, pred)
  -- Consider init.lua at this level first (for ordering), but just record it.
  local init_path = vim.fs.joinpath(dir, "init.lua")
  if is_file(init_path) then
    local mod = node.name
    if should_load(pred, mod, init_path) then
      node.init = choose_best(node.init, {
        mod = mod,
        path = init_path,
        priority = priority,
      })
    end
  end

  for name, t in vim.fs.dir(dir) do
    if not name:match("^[_%.]") then
      if t == "file" and name:sub(-4) == ".lua" and name ~= "init.lua" then
        local stem = name:sub(1, -5)
        local mod = ("%s.%s"):format(node.name, stem)
        local path = vim.fs.joinpath(dir, name)
        if should_load(pred, mod, path) then
          node.files[stem] = choose_best(node.files[stem], {
            mod = mod,
            path = path,
            priority = priority,
          })
        end
      elseif t == "directory" and recursive then
        local child_name = ("%s.%s"):format(node.name, name)
        local child = node.children[name]
        if not child then
          child = new_node(child_name)
          node.children[name] = child
        end
        scan_dir(child, vim.fs.joinpath(dir, name), priority, true, pred)
      end
    end
  end
end

---Emit requires in "init first, then files, then children" order.
---@param node DropinNode
---@param loaded string[]
---@param silent boolean
local function emit_node(node, loaded, silent)
  if node.init and safe_require(node.init.mod, silent) then
    table.insert(loaded, node.init.mod)
  end

  local stems = {}
  for stem, _ in pairs(node.files) do
    table.insert(stems, stem)
  end
  table.sort(stems)
  for _, stem in ipairs(stems) do
    local cand = node.files[stem]
    if safe_require(cand.mod, silent) then
      table.insert(loaded, cand.mod)
    end
  end

  local child_names = {}
  for name, _ in pairs(node.children) do
    table.insert(child_names, name)
  end
  table.sort(child_names)
  for _, name in ipairs(child_names) do
    emit_node(node.children[name], loaded, silent)
  end
end

---Load a module or directory of drop-ins across runtimepath.
--- - Directory mode (lua/<mod>/ exists on any RTP):
---   Load that directory's init.lua first (if present), then other files;
---   if recursive = true, recurse into subdirectories with the same rule.
--- - Single-file mode (lua/<mod>.lua exists, but no directory):
---   Load only that file (highest priority across RTP).
---@param mod string e.g. "config.dropins" or "config.dropins.alpha"
---@param opts? DropinLoaderOptions
---@return string[] loaded module names
function M.load_module(mod, opts)
  local o = vim.tbl_deep_extend("force", defaults, opts or {})
  local recursive = o.recursive or false
  local silent = o.silent or false

  ---@type DropinLoaderPredicate|nil
  local pred = o.predicate

  local loaded = {}

  -- Prefer directory mode if any lua/<mod>/ exists.
  local dirs = find_all_dirs(mod)
  if #dirs > 0 then
    local root = new_node(mod)
    for _, ent in ipairs(dirs) do
      local prio = rtp_priority(ent.rtp, ent.idx)
      scan_dir(root, ent.dir, prio, recursive, pred)
    end
    emit_node(root, loaded, silent)
    if not silent then
      vim.notify(
        ("dropins: loaded %d module(s) from %s"):format(#loaded, mod),
        vim.log.levels.INFO
      )
    end
    return loaded
  end

  -- Fall back to single-file mode if a file exists.
  local best = best_single_file_candidate(mod)
  if best and should_load(pred, best.mod, best.path) then
    if safe_require(best.mod, silent) then
      table.insert(loaded, best.mod)
    end
    if not silent then
      vim.notify(
        ("dropins: loaded 1 module (single): %s"):format(best.mod),
        vim.log.levels.INFO
      )
    end
    return loaded
  end

  if not silent then
    vim.notify(
      ("dropins: no matching module or directory for %q on runtimepath")
        :format(mod),
      vim.log.levels.WARN
    )
  end
  return {}
end

return M
