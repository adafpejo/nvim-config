local gh = function(x) return 'https://github.com/' .. x end
vim.pack.add({
    gh("nvim-lua/plenary.nvim"),          -- lua functions that many plugins use
    gh("christoomey/vim-tmux-navigator"), -- tmux & split window navigation
    gh("MunifTanjim/nui.nvim"),
    gh("mfussenegger/nvim-jdtls"),
    gh("L3MON4D3/LuaSnip"),

    -- mason
    gh("williamboman/mason.nvim"),

    -- nvim-treesetter
    gh("nvim-treesitter/nvim-treesitter"),
    gh("nvim-treesitter/nvim-treesitter-textobjects"),
    gh("nvim-mini/mini.nvim"),

    -- java
    gh("mfussenegger/nvim-jdtls"),

    -- dap
    gh("mfussenegger/nvim-dap"),
    gh("leoluz/nvim-dap-go"),
    gh("rcarriga/nvim-dap-ui"),
    gh("theHamsta/nvim-dap-virtual-text"),

    -- git
    gh("sindrets/diffview.nvim"),
    gh("kdheepak/lazygit.nvim"),
    gh("sindrets/diffview.nvim"),

    -- markdown
    gh("MeanderingProgrammer/render-markdown.nvim"),

    -- ui
    gh("rcarriga/nvim-notify"),
    gh("nvim-lualine/lualine.nvim"),
    gh("MunifTanjim/nui.nvim"),
    gh("folke/zen-mode.nvim"),

    -- lualine
    gh("nvim-lualine/lualine.nvim"),

    -- telescope
    gh("nvim-telescope/telescope.nvim"),
    gh("nvim-telescope/telescope-live-grep-args.nvim"),
    gh("nvim-telescope/telescope-fzf-native.nvim"),

    -- nvim-tree
    gh("nvim-tree/nvim-tree.lua"),
    gh("nvim-tree/nvim-web-devicons"),

    -- blink
    { src = gh("saghen/blink.cmp"), version = "v1" },
    gh("rafamadriz/friendly-snippets"),
    gh("echasnovski/mini.snippets"),

    -- colorshema
    gh("folke/tokyonight.nvim"),

    -- replace-all
    gh("MagicDuck/grug-far.nvim"),

    gh("tpope/vim-surround"),
    gh("tpope/vim-commentary"),
    gh("christoomey/vim-tmux-navigator"),
    gh("lewis6991/gitsigns.nvim"),

    -- harpoon
    gh("ThePrimeagen/harpoon"),

    -- xcode
    gh("wojciech-kulik/xcodebuild.nvim"),

    -- test
    gh("nvim-neotest/neotest"),
    gh("nvim-neotest/nvim-nio"),
    gh("antoinemadec/FixCursorHold.nvim"),

    gh("vim-test/vim-test"),
    gh("nvim-neotest/neotest-jest"),
    gh("marilari88/neotest-vitest"),
    gh("HiPhish/neotest-busted"),
    gh("thenbe/neotest-playwright"),
    gh("nvim-neotest/neotest-python"),
    gh("rcasia/neotest-java"),

    -- adapters
    { src = gh("nvim-neotest/neotest-go"), version = "05535cb2cfe3ce5c960f65784896d40109572f89" }, -- https://github.com/nvim-neotest/neotest-go/issues/57
    gh("andythigpen/nvim-coverage"),
    gh("stevearc/conform.nvim"),
})

require("core.mason-path")
require("core.mason-verify")
require("core.set")
require("core.lsp")

-- setup
require("plugin.mason")
require("plugin.blink")
require("plugin.gitsigns")
require("plugin.diffview")
require("plugin.nvim-tree")
require("plugin.lualine")
require("plugin.treesitter")
require("plugin.telescope")
require("plugin.test")
require("plugin.conform")

require("xcodebuild").setup({})
require("grug-far").setup({})

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

vim.schedule(function()
    require("bsi")
end)
