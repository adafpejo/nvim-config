return {
  cmd = {
    vim.fn.expand("~/.local/share/nvim/mason/bin/phpactor"),
    'language-server'
  },
  filetypes = { 'php' },
  root_markers = { '.git', 'composer.json', '.phpactor.json', '.phpactor.yml' },
  workspace_required = true,
}
