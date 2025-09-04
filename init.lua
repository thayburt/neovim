vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Initialize Lazy.Nvim dropin loader before loading Lazy.Nvim
require('utils.lazyconf').setup {
  config_dir = 'lazyconf',
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

local dropin_loader = require 'utils.dropconf'
dropin_loader.setup { recurse = true }
dropin_loader.load_modules 'config'
