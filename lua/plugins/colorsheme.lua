return {
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        ---@class CatppuccinOptions
        opts = {
            term_colors = true,
            transparent_background = false,
            styles = {
                comments = {},
                conditionals = {},
                loops = {},
                functions = {},
                keywords = {},
                strings = {},
                variables = {},
                numbers = {},
                booleans = {},
                properties = {},
                types = {},
            },
            integrations = {
                telescope = {
                    enabled = true,
                    style = "nvchad",
                },
                dropbar = {
                    enabled = true,
                    color_mode = true,
                },
            },
        },
    },

    -- Configure LazyVim to load gruvbox
    {
        "LazyVim/LazyVim",
        opts = {
            colorscheme = "catppuccin",
        },
    },
}
