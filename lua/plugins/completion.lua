return {
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
        library = {
            {
                path = "${3rd}/luv/library",
                words = { "vim%.uv" },
            },
        },
    },
  },

  {
    'saghen/blink.cmp',
    dependencies = {
        'L3MON4D3/LuaSnip',
        version = 'v2.*',
    },
    version = '1.*',
    opts = {
        snippets = { preset = 'luasnip' },
        sources = {
            default = { 'lsp', 'path', 'snippets', 'buffer' },
            per_filetype = {
                lua = { inherit_defaults = true, 'lazydev' }
            },
            providers = {
                lazydev = {
                    name = "LazyDev",
                    module = "lazydev.integrations.blink",
                    score_offset = 100,
                },
            },
        }
    },
  },
  {
    'saghen/blink.compat',
    version = '2.*',
    lazy = true,
  }
}
