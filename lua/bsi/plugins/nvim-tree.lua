return {
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = {
            "nvim-tree/nvim-web-devicons"
        },
        config = function()
            local api = require('nvim-tree.api');

            require('nvim-tree').setup({
                filters = {
                    enable = false
                },
                renderer = {
                    highlight_modified = "all",
                    highlight_git = true,
                    icons = {
                        glyphs = {
                            git = {
                                untracked = "[?]",
                                ignored = ""
                            }
                        }
                    }
                }
            })

            vim.keymap.set(
                "n",
                "<leader>ee",
                function()
                    api.tree.toggle()
                end,
                { desc = "NvimTreeToggle" }
            )
        end
    }
}
