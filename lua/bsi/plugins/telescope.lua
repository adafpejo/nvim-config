return {
    -- change telescope config
    {
        "nvim-telescope/telescope.nvim",
        dependencies = {
            {
                "nvim-telescope/telescope-fzf-native.nvim", -- https://github.com/nvim-telescope/telescope-fzf-native.nvim
                build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build",
            },
            "nvim-telescope/telescope-live-grep-args.nvim", -- https://github.com/nvim-telescope/telescope-live-grep-args.nvim
            {
                "ahmedkhalf/project.nvim",
                config = function()
                    require("project_nvim").setup({
                        patterns = {
                            ".git",
                            "go.mod",
                        },
                        base_dirs = {
                            { "~/_git", max_depth = 3 },
                            { "~/_semhub", max_depth = 3 },
                            { "~/_my", max_depth = 3 },
                        },
                    })
                end,
            },
        },
        -- opts will be merged with the parent spec
        opts = {
            defaults = {
                file_ignore_patterns = { ".git/", "node_modules", "poetry.lock" },
                vimgrep_arguments = {
                    "rg",
                    "--color=never",
                    "--no-heading",
                    "--hidden",
                    "--with-filename",
                    "--line-number",
                    "--column",
                    "--smart-case",
                    "--trim",
                },
            },
        })

        telescope.load_extension("fzf")

        -- set keymaps
        local keymap = vim.keymap -- for conciseness

        keymap.set("n", "<leader><leader>", "<cmd>Telescope find_files<cr>", { desc = "Fuzzy find files in cwd" })
        keymap.set("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Fuzzy find recent files" })
        keymap.set("n", "<leader>fs", "<cmd>Telescope live_grep<cr>", { desc = "Find string in cwd" })
        keymap.set("n", "<leader>fc", "<cmd>Telescope grep_string<cr>", { desc = "Find string under cursor in cwd" })
    end,
}
