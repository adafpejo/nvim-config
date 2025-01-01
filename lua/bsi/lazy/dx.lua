return {
    {
        "folke/zen-mode.nvim",
        keys = {
            { "<leader>z", "<cmd>Zen<CR>", { desc = "Zen mod" } },
        },
    },
    { "David-Kunz/gen.nvim" },
    {
        "rmagatti/auto-session",
        lazy = false,
        dependencies = {
            "nvim-telescope/telescope.nvim", -- Only needed if you want to use sesssion lens
        },
        config = function()
            require("auto-session").setup({
                auto_session_suppress_dirs = { "~/", "~/Projects", "~/Downloads", "/" },
            })
        end,
    },
    -- -- Create annotations with one keybind, and jump your cursor in the inserted annotation
    -- {
    --     "danymat/neogen",
    --     keys = {
    --         {
    --             "<leader>cc",
    --             function()
    --                 require("neogen").generate({})
    --             end,
    --             desc = "Neogen Comment",
    --         },
    --     },
    --     opts = { snippet_engine = "luasnip" },
    -- },
    {
        "tpope/vim-surround",
    },
    {
        "tpope/vim-commentary",
    },
    -- https://devdocs.io fast lookup
    {
        "luckasRanarison/nvim-devdocs",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope.nvim",
            "nvim-treesitter/nvim-treesitter",
        },
        opts = {},
        -- opts = {
        --     ensure_installed = {
        --         "react",
        --         "typescript",
        --         "vite",
        --         "playwright",
        --         "html",
        --         "css",
        --         "http",
        --         "dom",
        --         "bash",
        --         "docker",
        --         "eslint",
        --         "express",
        --         "esbuild",
        --         "git",
        --         "go",
        --         "jest",
        --         "vitest",
        --         "nginx",
        --         "node"
        --     },
        -- }
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

            { "<leader>ha", ":lua require('harpoon.mark').add_file()<CR>", desc = "Add file as marked" },
            { "<leader>hn", ":lua require('harpoon.ui').nav_next()<CR>", desc = "Next file" },
            { "<leader>hp", ":lua require('harpoon.ui').nav_prev()<CR>", desc = "Previous file" },
            { "<leader>ht", ":lua require('harpoon.term').gotoTerminal(1)<CR>", desc = "Terminal" },
        },
    },
    {
    'MagicDuck/grug-far.nvim',
    config = function()
      require('grug-far').setup({
        -- options, see Configuration section below
        -- there are no required options atm
        -- engine = 'ripgrep' is default, but 'astgrep' can be specified
      });
    end
  },
}
