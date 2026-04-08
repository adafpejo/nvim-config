require("conform").setup({
  formatters_by_ft = {
    go = { "goimports", "gofmt" },
    lua = { "stylua" },
    python = { "isort", "black" },
    php = { "pint" },
    sh = { "shfmt" },
    bash = { "shfmt" },
    rust = { "rustfmt" },
  },
  default_format_opts = {
    lsp_format = "fallback",
  },
})
