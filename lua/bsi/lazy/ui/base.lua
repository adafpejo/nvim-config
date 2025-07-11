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
                    width = 40,
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
                                untracked = "[?]",
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
                end,
            })

            vim.keymap.set("n", "<leader>ee", function()
                nt_api.tree.toggle({ find_file = true })
            end, { desc = "NvimTreeToggle" })
        end,
    },
    {
        "akinsho/bufferline.nvim",
        enabled = false,
        dependencies = { "nvim-tree/nvim-web-devicons" },
        version = "*",
        keys = {
            { "<leader>bp", "<Cmd>BufferLineTogglePin<CR>",            desc = "Toggle pin" },
            { "<leader>bP", "<Cmd>BufferLineGroupClose ungrouped<CR>", desc = "Delete non-pinned buffers" },
            { "<leader>bo", "<Cmd>BufferLineCloseOthers<CR>",          desc = "Delete other buffers" },
            { "<leader>br", "<Cmd>BufferLineCloseRight<CR>",           desc = "Delete buffers to the right" },
            { "<leader>bl", "<Cmd>BufferLineCloseLeft<CR>",            desc = "Delete buffers to the left" },
            { "<leader>bd", "<Cmd>:bp|bd#<CR>",                        desc = "Close current buffer" },
            { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",            desc = "Prev buffer" },
            { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",            desc = "Next buffer" },
            { "[b",         "<cmd>BufferLineCyclePrev<cr>",            desc = "Prev buffer" },
            { "]b",         "<cmd>BufferLineCycleNext<cr>",            desc = "Next buffer" },
        },
        config = function()
            require("bufferline").setup({
                options = {
                    -- stylua: ignore
                    close_command = function(n) require("mini.bufremove").delete(n, false) end,
                    -- stylua: ignore
                    right_mouse_command = function(n) require("mini.bufremove").delete(n, false) end,
                    diagnostics = "nvim_lsp",
                    enforce_regular_tabs = true,
                    always_show_bufferline = true,
                    auto_toggle_bufferline = true,
                    offsets = {
                        {
                            filetype = "NvimTree",
                            text = "File Explorer",
                            text_align = "center",
                        },
                    },
                },
            })
        end,
    },
}
