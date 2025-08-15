local dx = require "bsi.dx"
return {
    { "rcarriga/nvim-notify" },
    {
        "kdheepak/lazygit.nvim",
        cmd = {
            "LazyGit",
            "LazyGitConfig",
            "LazyGitCurrentFile",
            "LazyGitFilter",
            "LazyGitFilterCurrentFile",
        },
        -- optional for floating window border decoration
        dependencies = {
            "nvim-lua/plenary.nvim",
        },
        -- setting the keybinding for LazyGit with 'keys' is recommended in
        -- order to load the plugin when the command is run for the first time
        keys = {
            { "<leader>lg", "<cmd>LazyGit<cr>", desc = "LazyGit" },
        },
    },
    -- file explorer sidebar
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = {
            "nvim-tree/nvim-web-devicons",
        },
        config = function()
            local nt_api = require("nvim-tree.api")

            require("nvim-tree").setup({
                update_focused_file = {
                    enable = true,
                },
                filters = {
                    enable = false,
                },
                view = {
                    width = 30,
                },
                git = {
                    enable = true,
                    disable_for_dirs = {
                        "node_modules",
                    },
                },
                renderer = {
                    highlight_modified = "all",
                    highlight_git = true,
                    group_empty = true,
                    icons = {
                        glyphs = {
                            git = {
                                untracked = "?",
                                ignored = "",
                            },
                        },
                    },
                },
                filesystem_watchers = {
                    ignore_dirs = {
                        "node_modules",
                    },
                },
                on_attach = function(bufnr)
                    local api = require("nvim-tree.api")
                    api.config.mappings.default_on_attach(bufnr)
                    vim.keymap.del('n', '<C-k>', {
                        buffer = bufnr
                    })
                    local function map(lhs, rhs, desc)
                        vim.keymap.set("n", lhs, rhs,
                            { buffer = bufnr, noremap = true, silent = true, desc = "nvim-tree: " .. desc })
                    end

                    -- Open with system default app (Finder, browser, PDF viewer, etc.)
                    map("o", function()
                        local node = api.tree.get_node_under_cursor()
                        if node then dx.open_url(node.absolute_path) end
                    end, "Open with System (Browser/Finder)")

                    -- macOS: “Reveal in Finder”
                    map("of", function()
                        local node = api.tree.get_node_under_cursor()
                        if not node then return end
                        if vim.loop.os_uname().sysname == "Darwin" then
                            -- -R reveals the file in Finder
                            vim.fn.jobstart({ "open", "-R", node.absolute_path }, { detach = true })
                        else
                            -- Fallback: just open with system handler on non-macOS
                            dx.open_url(node.absolute_path)
                        end
                    end, "Reveal in Finder")
                end,
            })

            vim.keymap.set("n", "<leader>ee", function()
                nt_api.tree.toggle({ find_file = true })
            end, { desc = "NvimTreeToggle" })
        end,
    },
}
