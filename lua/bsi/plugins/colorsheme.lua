return {
    {
        "folke/tokyonight.nvim",
        lazy = false,
        priority = 1000,
        opts = {},
        config = function()
            vim.cmd([[colorscheme tokyonight-night]])
        end,
    },
    { "catppuccin/nvim",                  name = "catppuccin", priority = 1000 },
    { "embark-theme/vim",                 name = "embark",     priority = 1000 },
    { "nyoom-engineering/oxocarbon.nvim", name = "oxocarbon",  priority = 1000 },
}
