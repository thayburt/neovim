vim.keymap.set({ 'n', 'i' }, '<c-n>', function()
  require('clasp').wrap 'next'
end)
vim.keymap.set({ 'n', 'i' }, '<c-b>', function()
  require('clasp').wrap 'prev'
end)

