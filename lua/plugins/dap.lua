return {
  'mfussenegger/nvim-dap',
  {
    'theHamsta/nvim-dap-virtual-text',
    dependencies = {
      'mfussenegger/nvim-dap',
    },
    ---@module 'nvim-dap-virtual-text'
    ---@type nvim_dap_virtual_text_options
    opts = {},
  },
  {
    'nvim-telescope/telescope-dap.nvim',
    dependencies = {
      'mfussenegger/nvim-dap',
      'nvim-telescope/telescope.nvim',
    },
    config = function()
      require('telescope').load_extension 'dap'
    end,
  },
}
