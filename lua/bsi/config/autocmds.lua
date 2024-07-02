-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

vim.api.nvim_create_autocmd({ "FileType" }, {
    pattern = { "json", "jsonc", "json5", "markdown" },
    callback = function()
        vim.wo.conceallevel = 0
        vim.opt_local.tabstop = 2
        vim.opt_local.softtabstop = 2
        vim.opt_local.shiftwidth = 2
    end,
})

vim.cmd("hi GitIgnore guifg=#ff0000")
vim.cmd("hi NvimTreeGitIgnored guifg=#ff0000")
vim.cmd("hi NvimTreeGitFileIgnoredHL guifg=gray")
vim.cmd("hi NvimTreeGitFolderIgnoredHL guifg=gray")

for _, group in ipairs(vim.fn.getcompletion("@lsp", "highlight")) do
    vim.api.nvim_set_hl(0, group, {})
end

-- function _G.set_terminal_keymaps()
--     local opts = { buffer = 0 }
--     vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], opts)
--     vim.keymap.set("t", "jk", [[<C-\><C-n>]], opts)
--     vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], opts)
--     vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], opts)
--     vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], opts)
--     vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], opts)
--     vim.keymap.set("t", "<C-w>", [[<C-\><C-n><C-w>]], opts)
-- end
--
-- -- If you specifically want these mappings only for toggle term, you can adjust the pattern as follows:
-- vim.api.nvim_create_autocmd("TermOpen", {
--     pattern = "term://*toggleterm#*",
--     callback = function()
--         _G.set_terminal_keymaps()
--     end,
-- })
