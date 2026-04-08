require("core.mason-path")
require("core.mason-verify")
require("core.pack")

-- custom
vim.schedule(function()
    require("core.set")
    require("core.lsp")
    require("core.keymap")
    require("bsi")
end)

vim.diagnostic.config({
    underline = true,
    virtual_text = true,
    update_in_insert = false,
    severity_sort = true,
    float = {
        border = "rounded",
        source = true,
    },
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = "E ",
            [vim.diagnostic.severity.WARN] = "W ",
            [vim.diagnostic.severity.INFO] = "I ",
            [vim.diagnostic.severity.HINT] = "H ",
        },
        numhl = {
            [vim.diagnostic.severity.ERROR] = "ErrorMsg",
            [vim.diagnostic.severity.WARN] = "WarningMsg",
        },
    },
})

-- colorscheme
vim.cmd.colorscheme("tokyonight-night")

-- keymap
vim.keymap.set("n", "<leader>lg", "<cmd>LazyGit<cr>", { desc = "LazyGit" })

vim.keymap.set("n", "<leader>z", "<cmd>Zen<CR>", { desc = "Zen mod" })

vim.keymap.set("n", "<leader>hh", ":lua require('harpoon.ui').toggle_quick_menu()<CR>", { desc = "Harpoon menu" })
-- vim.keymap.set("n", "<leader>ht", ":Telescope harpoon marks<CR>", { desc = "Telescope menu" })

-- harpoon keymap
vim.keymap.set("n", "<leader>ha", ":lua require('harpoon.mark').add_file()<CR>", { desc = "Add file as marked" })
vim.keymap.set("n", "<leader>hn", ":lua require('harpoon.ui').nav_next()<CR>", { desc = "Next file" })
vim.keymap.set("n", "<leader>hp", ":lua require('harpoon.ui').nav_prev()<CR>", { desc = "Previous file" })
vim.keymap.set("n", "<leader>ht", ":lua require('harpoon.term').gotoTerminal(1)<CR>", { desc = "Terminal" })
