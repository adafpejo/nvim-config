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
vim.keymap.set("n", "<leader>lg", "<cmd>LazyGit<cr>", { desc = "LazyGit", noremap = true })
vim.keymap.set("n", "<leader>z", "<cmd>Zen<CR>", { desc = "Zen mod", noremap = true })

-- harpoon keymap
vim.keymap.set("n", "<leader>hh", ":lua require('harpoon.ui').toggle_quick_menu()<CR>", { desc = "Harpoon menu", noremap = true })
vim.keymap.set("n", "<leader>ht", ":Telescope harpoon marks<CR>", { desc = "Telescope menu", noremap = true })
vim.keymap.set("n", "<leader>ha", ":lua require('harpoon.mark').add_file()<CR>", { desc = "Add file as marked", noremap = true })
vim.keymap.set("n", "<leader>hn", ":lua require('harpoon.ui').nav_next()<CR>", { desc = "Next file", noremap = true })
vim.keymap.set("n", "<leader>hp", ":lua require('harpoon.ui').nav_prev()<CR>", { desc = "Previous file", noremap = true })
vim.keymap.set("n", "<leader>ht", ":lua require('harpoon.term').gotoTerminal(1)<CR>", { desc = "Terminal", noremap = true })

vim.schedule(function()
    vim.lsp.handlers['textDocument/hover'] = function(err, result, ctx, config)
        vim.notify('hover handler called', vim.log.levels.INFO)
        if result and result.contents then
            local value = type(result.contents) == 'table'
                and result.contents.value
                or result.contents

            value = value:gsub('%[([^%]]+)%]%(jdt://[^%)]+%)', '`%1`')
            value = value:gsub('jdt://%S+', '')
            value = value:gsub(' %*  ', '• ')
            value = value:gsub('\n\n\n+', '\n\n')
            value = value:gsub('\n%s+\n', '\n\n')

            if type(result.contents) == 'table' then
                result.contents.value = value
            else
                result.contents = value
            end
        end
        vim.lsp.handlers['textDocument/hover'](err, result, ctx, config)
    end
end)
