return {
  {
    'neovim/nvim-lspconfig',
    version = nil,
  },
  {
    'p00f/clangd_extensions.nvim',
    opts = {},
  },
  {
    'mrcjkb/rustaceanvim',
    version = '^6',
    lazy = false,
  },
  {
    'seblyng/roslyn.nvim',
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {},
  },
}
