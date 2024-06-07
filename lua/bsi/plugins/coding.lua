return {
    {
        "folke/zen-mode.nvim",
        keys = {
            { "<leader>z", "<cmd>Zen<CR>", { desc = "Zen mod" } }
        }
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
    }
}
