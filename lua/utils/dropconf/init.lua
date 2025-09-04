local M = {}

---@alias dropconf.FoundFiles table<string, string[]>
---@alias dropconf.LoadResults any[]
---@alias dropconf.RecursionDepth boolean|number

---@class dropconf.Config
---@field finder fun(paths: string[], recurse: dropconf.RecursionDepth): dropconf.FoundFiles find all files within the set paths
---@field filter_module fun(module: string): boolean True to include the given lua module
---@field filter_path fun(path: string): boolean True to include the given file path
---@field recurse dropconf.RecursionValue Should the function recurse and what depth (true for infinite, false for no recursion)

---@class dropconf.PartialConfig
---@field finder? fun(paths: string[], recurse: dropconf.RecursionDepth): dropconf.FoundFiles find all files within the set paths
---@field filter_module? fun(module: string): boolean True to include the given lua module
---@field filter_path? fun(path: string): boolean True to include the given file path
---@field recurse? dropconf.RecursionValue Should the function recurse and what depth (true for infinite, false for no recursion)

---@type dropconf.Config
local defaults = {
  -- The active function used to find files. Set during initialization.
  ---@diagnostic disable-next-line: assign-type-mismatch
  finder = nil,
  -- A function to filter modules by their name (e.g., 'config.plugins.lualine').
  -- Default is to load all modules.
  filter_module = function()
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

if vim.fn.executable 'fd' == 1 or vim.fn.executable 'fdfind' == 1 then
  defaults.finder = require 'utils.dropconf.fd_find'
else
  defaults.finder = require 'utils.dropconf.lua_find'
end

---@param search_paths string[] list of paths to search
---@param options dropconf.PartialConfig Overriding config values for this specific load
---@return dropconf.LoadResults results the return values of the loaded files
local function _internal_load(search_paths, options)
  local opts = vim.tbl_deep_extend('keep', options, defaults)

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
      vim.notify(("dropconf: error loading module: '%s'\n%s"):format(mod.name, tostring(ret)), vim.log.levels.ERROR)
    elseif ret ~= nil then
      table.insert(results, ret)
    end
  end

  return results
end

---@param paths string|string[] all paths to load from
---@param load_config dropconf.PartialConfig|nil config overrides for specific load request
---@return dropconf.LoadResults results the return values of the loaded files
function M.load_paths(paths, load_config)
  local pathType = type(paths)
  local validPaths = {}
  if pathType == type '' then
    ---@cast paths -string[]
    validPaths = { paths }
  elseif pathType ~= type {} then
    vim.notify(("dropconf: error: found parameter '%s' is of unsupported type '%s'"):format('paths', pathType), vim.log.levels.ERROR)
  else
    ---@cast paths -string
    for index, path in ipairs(paths) do
      if type(path) == type '' then
        table.insert(validPaths, path)
      else
        vim.notify(
          ("dropconf: warning: found value of unsupported type '%s' within '%s' at index '%s'. Skipping"):format(type(path), 'paths', tostring(index)),
          vim.log.levels.WARN
        )
      end
    end
  end
  return _internal_load(validPaths, load_config or {})
end

---@param modules string|string[] the starting subdirectory to search from in runtime paths
---@param load_config dropconf.PartialConfig|nil config overrides for specific load request
---@return dropconf.LoadResults results the return values of the loaded files
function M.load_modules(modules, load_config)
  local modType = type(modules)
  if modType == type '' then
    local module_list = { modules }
    modules = module_list
  elseif modType ~= type {} then
    vim.notify(("dropconf: error: found parameter '%s' is of unsupported type '%s'"):format('modules', modType), vim.log.levels.ERROR)
  end
  ---@cast modules string[]
  local search_paths = {}
  local rtp = vim.api.nvim_list_runtime_paths()

  for index, mod_name in ipairs(modules) do
    if type(mod_name) == 'string' then
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
    else
      vim.notify(
        ("dropconf: warning: found value of unsupported type '%s' within '%s' at index '%s'. Skipping"):format(type(mod_name), 'modules', tostring(index)),
        vim.log.levels.WARN
      )
    end
  end

  if #search_paths == 0 then
    return {}
  end
  return _internal_load(search_paths, load_config or {})
end

---@param config dropconf.PartialConfig Configuration table with the following keys:
function M.setup(config)
  defaults = vim.tbl_deep_extend('keep', config or {}, defaults)
end

return M
