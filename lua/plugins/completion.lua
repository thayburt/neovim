---@param base string
---@param arg string
---@return string|nil
local function build_arg(base, arg)
  local log_msg = nil
  local msg_fmt = "ERROR: build_arg argument '%s' is not a string, was type: '%s'"
  if type(base) ~= type '' then
    log_msg = (msg_fmt):format('base', type(base))
  elseif type(arg) ~= type '' then
    log_msg = (msg_fmt):format('arg', type(arg))
  end
  if log_msg then
    vim.notify(log_msg, vim.log.levels.ERROR)
  else
    return ('%s %s'):format(base, arg)
  end
  return base
end
---@param args string[]|string
---@return false|string build_result
local function cargo_build(args)
  if vim.fn.executable 'cargo' == 1 then
    local arg_string = 'cargo build'
    if type(args) == type {} then
      for arg in args do
        arg_string = build_arg(arg_string, arg)
      end
    else
      arg_string = build_arg(arg_string, args)
    end
    return arg_string
  end
  return false
end

return {
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        {
          path = '${3rd}/luv/library',
          words = { 'vim%.uv' },
        },
        'lazy.nvim',
      },
      enabled = function(root_dir)
        if vim.uv.fs_stat(root_dir .. '/.luarc.json') then
          return false
        end
        return vim.g.lazydev_enabled == nil and true or vim.g.lazydev_enabled
      end,
    },
  },
  {
    'saghen/blink.cmp',
    version = '1.*',
    build = cargo_build '--release',
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
        per_filetype = {
          lua = { inherit_defaults = true, 'lazydev' },
        },
        providers = {
          lazydev = {
            name = 'LazyDev',
            module = 'lazydev.integrations.blink',
            score_offset = 100,
          },
        },
      },
    },
  },
  {
    'saghen/blink.compat',
    version = '2.*',
    lazy = true,
  },
  {
    'saghen/blink.pairs',
    build = cargo_build '--release',
    ---@module 'blink.pairs'
    ---@type blink.pairs.Config
    opts = {},
  },
}
