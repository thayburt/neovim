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
    build = 'cargo build --release',
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
    build = 'cargo build --release',
    ---@module 'blink.pairs'
    ---@type blink.pairs.Config
    opts = {},
  },
}
