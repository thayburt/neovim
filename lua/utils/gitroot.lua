---@type Gitroot
---@field get_root fun(path: string) Get the path to the git root if any
local M = {}

function M.get_root(path)
  path = path or vim.fn.expand '%:p:h'
  local result = vim
    .system({ 'git', 'rev-parse', '--show-toplevel' }, {
      text = true,
      cwd = path,
    })
    :wait()
  if result.code ~= 0 then
    return nil
  end
  return result.stdout
end

return M
