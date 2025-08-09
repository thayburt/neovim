local capabilities = vim.lsp.protocol.make_client_capabilities()

local lspconfig = require 'lspconfig'

lspconfig.omnisharp.setup {
  capabilities = capabilities,
}

lspconfig.lemminx.setup {
  capabilities = capabilities,
  settings = {
    xml = {
      catalogs = {},
    },
  },
}
lspconfig.lua_ls.setup {
  capabilities = capabilities,
}
