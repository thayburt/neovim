
vim.cmd [[colorscheme eldritch]]

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.shiftwidth = 0 -- Use tabstop's value
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
-- Placed after UiEnter for startup time concerns mentioned in kickstart.nvim
vim.schedule(function()
  vim.opt.clipboard = 'unnamedplus'
end)

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
