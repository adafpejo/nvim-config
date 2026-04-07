local gh = function(x) return 'https://github.com/' .. x end
vim.pack.add({
    "https://github.com/nvim-lua/plenary.nvim",          -- lua functions that many plugins use
    "https://github.com/christoomey/vim-tmux-navigator", -- tmux & split window navigation
    "https://github.com/MunifTanjim/nui.nvim",
    'https://github.com/mfussenegger/nvim-jdtls',
    "https://github.com/L3MON4D3/LuaSnip",

    -- java
    gh('mfussenegger/nvim-jdtls'),

    -- dap
    "https://github.com/mfussenegger/nvim-dap",
    "https://github.com/leoluz/nvim-dap-go",
    "https://github.com/rcarriga/nvim-dap-ui",
    "https://github.com/theHamsta/nvim-dap-virtual-text",

    -- git
    gh('sindrets/diffview.nvim'),
    gh("https://github.com/kdheepak/lazygit.nvim"),
    'https://github.com/sindrets/diffview.nvim',

    -- ui
    "https://github.com/rcarriga/nvim-notify",
    "https://github.com/nvim-lualine/lualine.nvim",
    gh("MunifTanjim/nui.nvim"),
    gh("folke/zen-mode.nvim"),

    -- blink
    "https://github.com/saghen/blink.cmp",
    "https://github.com/rafamadriz/friendly-snippets",

    -- colorshema
    { src = "https://github.com/folke/tokyonight.nvim", name = 'tokyonight' },

    gh("tpope/vim-surround"),
    gh("tpope/vim-commentary"),
    gh("christoomey/vim-tmux-navigator"),
    gh("lewis6991/gitsigns.nvim"),
})

require("core.mason-path")
require("core.mason-verify")
require("core.set")
require("core.lsp")
require("bsi")
require("plugin.blink")
require("plugin.gitsigns")
require("plugin.diffview")

vim.cmd.colorscheme("tokyonight-night")

-- keymap
vim.keymap.set("n", "<leader>lg", "<cmd>LazyGit<cr>", { desc = "LazyGit" })

vim.keymap.set("n", "<leader>z", "<cmd>Zen<CR>", { desc = "Zen mod" })

