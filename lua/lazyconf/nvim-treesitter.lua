require('nvim-treesitter').install {
  'bash',
  'c',
  'c_sharp',
  'cpp',
  'editorconfig',
  'erlang',
  'go',
  'hyprlang',
  'javascript',
  'make',
  'markdown',
  'nasm',
  'python',
  'rust',
  'tmux',
  'toml',
  'tsx',
  'typescript',
  'udev',
  'vim',
  'vimdoc',
  'xml',
  'yaml',
  'zig',
}

vim.api.nvim_create_autocmd('FileType', {
  pattern = { '<filetype>' },
  callback = function()
    vim.treesitter.start()
  end,
})
vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
