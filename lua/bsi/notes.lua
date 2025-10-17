vim.keymap.set({"n", "v"}, "<leader>nt", function()
  vim.api.nvim_put({ "## " .. os.date("%Y-%m-%d") }, "c", true, true)
end, { desc = "Insert timestamp (YYYY-MM-DD)" })

vim.keymap.set({"n", "v"}, "<leader>nts", function()
  vim.api.nvim_put({ "## " .. os.date("%Y-%m-%d %H:%S") }, "c", true, true)
end, { desc = "Insert timestamp (YYYY-MM-DD)" })

