return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    branch = 'main',
    ---@module 'nvim-treesitter'
    ---@type TSConfig
    opts = {
      install_dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'site'),
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
    },
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    ---@module 'treesitter-context'
    ---@type TSContext.UserConfig
    opts = {},
  },
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
    },
    branch = 'main',
    ---@module 'nvim-treesitter-textobjects'
    ---@type TSTextObjects.UserConfig
    opts = {},
  },
}
