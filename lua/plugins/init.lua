return {
    "nvim-lua/plenary.nvim", -- lua functions that many plugins use
    "christoomey/vim-tmux-navigator", -- tmux & split window navigation
    "MunifTanjim/nui.nvim",
    'sindrets/diffview.nvim', -- git diff view buffer

    -- render images
    { "3rd/image.nvim", build = false, opts = { backend = "kitty" } },
}
