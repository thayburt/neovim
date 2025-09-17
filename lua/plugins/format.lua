return {
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format { async = true }
      end,
      mode = '',
      desc = 'Format Buffer',
    },
  },
  ---@module "conform"
  ---@type conform.setupOpts
  opts = {
    formatters_by_ft = {
      c = { 'clang_format' },
      cpp = { 'clang_format' },
      erl = { 'erlfmt' },
      go = { 'gofmt', 'goimports' },
      python = { 'ruff_organize_imports', 'ruff_fix', 'ruff_format' },
      lua = { 'stylua' },
      rust = { 'rustfmt' },
      sh = { 'shfmt' },
      zig = { 'zigfmt' },
    },
    formatters = {
      clang_format = {
        args = { '--style=file', '--fallback-style=Google' },
      },
    },
  },
}
