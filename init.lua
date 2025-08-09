vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Initialize Lazy.Nvim dropin loader before loading Lazy.Nvim
require('utils.lazyconf').setup {
  config_dir = 'lua/lazyconf',
}

require('lazy').setup {
  spec = { { import = 'plugins' } },
  checker = { enabled = true },
  defaults = {
    version = '*',
  },
  install = {
    missing = true,
    colorscheme = { 'eldritch' },
  },
}

local dropin_loader = require 'utils.dropins'
dropin_loader.setup { recursive = true }
dropin_loader.load_module 'config'
