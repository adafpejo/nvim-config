return {
    {
        "folke/zen-mode.nvim",
        keys = {
            { "<leader>z", "<cmd>Zen<CR>", { desc = "Zen mod" } }
        }
    },
    -- load luasnips + cmp related in insert mode only
    {
        "nvimdev/epo.nvim",
        event = "InsertEnter",
        config = function()
            require("epo").setup({
                fuzzy = true,
                debounce = 0,
                signature = true,
                -- snippet_path = nil,
                -- signature_border = "rounded",

                -- kind_format = function(k)
                -- 	return k:lower():sub(1, 1)
                -- end,
            })
        end,
    },
    -- remember sessions by project
    {
        'rmagatti/auto-session',
        config = function()
            require("auto-session").setup {
                log_level = "error",
            }
        end
    },
    -- Create annotations with one keybind, and jump your cursor in the inserted annotation
    {
        "danymat/neogen",
        keys = {
            {
                "<leader>cc",
                function()
                    require("neogen").generate({})
                end,
                desc = "Neogen Comment",
            },
        },
        opts = { snippet_engine = "luasnip" },
    },
    {
        "tpope/vim-surround",
    },
    {
        "tpope/vim-commentary",
    },
    {
        "ThePrimeagen/harpoon",
        dependencies = {
            { "nvim-lua/plenary.nvim" },
            { "nvim-telescope/telescope.nvim" },
        },
        keys = {
            { "<leader>hh", ":lua require('harpoon.ui').toggle_quick_menu()<CR>", desc = "Harpoon menu" },
            -- { "<leader>ht", ":Telescope harpoon marks<CR>", desc = "Telescope menu" },

            { "<leader>ha", ":lua require('harpoon.mark').add_file()<CR>",        desc = "Add file as marked" },
            { "<leader>hn", ":lua require('harpoon.ui').nav_next()<CR>",          desc = "Next file" },
            { "<leader>hp", ":lua require('harpoon.ui').nav_prev()<CR>",          desc = "Previous file" },
            { "<leader>ht", ":lua require('harpoon.term').gotoTerminal(1)<CR>",   desc = "Terminal" },
        },
    },
}
