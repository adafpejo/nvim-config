local keymap = vim.keymap

keymap.set({ "n", "v" }, "<leader>cf", function()
  require("conform").format({ async = true }, function(err, did_edit)
    if not err and did_edit then
      vim.notify("Code formatted", vim.log.levels.INFO, { title = "Conform" })
    end
  end)
end, { desc = "Format buffer" })

vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

local opts = {
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
}

require("conform").setup(opts)