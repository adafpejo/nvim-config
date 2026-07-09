---@brief
---
--- https://github.com/phpactor/phpactor
---
--- Phpactor is a PHP language server with excellent support for
--- completion, refactoring, and navigation. It works best in projects
--- that have a `composer.json`.
---
--- Configuration is primarily done via `.phpactor.json` or `.phpactor.yml`
--- in your project root (recommended for per-repo settings).
---
--- Mason package: "phpactor"

local blink = require("blink.cmp")

return {
  cmd = {
    vim.fn.expand("~/.local/share/nvim/mason/bin/phpactor"),
    "language-server",
  },
  filetypes = { "php" },
  root_markers = {
    "composer.json",
    ".phpactor.json",
    ".phpactor.yml",
    ".git",
  },
  workspace_required = true,

  capabilities = vim.tbl_deep_extend(
    "force",
    {},
    vim.lsp.protocol.make_client_capabilities(),
    blink.get_lsp_capabilities()
  ),

  -- Most phpactor behavior is controlled by project-level config files.
  -- You can still override some things here if desired.
  settings = {
    phpactor = {
      -- Example toggles (most users configure via .phpactor.yml instead):
      -- completion = { enabled = true },
      -- diagnostics = { enabled = true },
      -- index = { enabled = true },
    },
  },

  -- Useful for large projects: you can increase memory via project config
  -- or by extending the cmd here, e.g.:
  -- cmd = { ".../phpactor", "language-server", "--memory-limit=2G" },
}
