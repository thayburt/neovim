local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system {
        'git',
        'clone',
        '--filter=blob:none',
        'https://github.com/folke/lazy.nvim.git',
        '--branch=stable', -- latest stable release
        lazypath,
    }
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

require("lazy").setup({
    spec = { { import = "plugins" }, },
    checker = { enabled = true },
    defaults = {
        version = "*"
    },
    install = {
        missing = true,
        colorscheme = { "eldritch" },
    },
    lockfile = vim.fn.stdpath 'data' .. '/lazy/lazy-lock.json'
})

vim.cmd[[colorscheme eldritch]]

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.shiftwidth = 0  -- Use tabstop's value
vim.opt.shiftround = true

vim.opt.scrolloff = 8

vim.opt.smartindent = true
vim.opt.autoindent = true

-- Relative Line Numbers
vim.opt.nu = true
vim.opt.relativenumber = true

-- Highlight active cursor
vim.opt.cursorline = true
vim.opt.cursorlineopt = 'number'

-- Sync clipboard to Wayland env
vim.opt.clipboard = 'unnamedplus'

vim.opt.signcolumn = 'auto:1-3'

-- Backup file only when writing
vim.opt.backup = false
vim.opt.writebackup = true
vim.opt.backupcopy = 'yes'
vim.opt.backupext = '.bak'

vim.opt.updatetime = 3000
vim.opt.swapfile = true
vim.opt.undofile = true

vim.opt.completeopt = 'menu,fuzzy,noselect,preview'

require('config.lspconfig')
