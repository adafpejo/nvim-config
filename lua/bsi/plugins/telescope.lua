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
            extensions = {
                fzf = {},
                live_grep_args = {},
                projects = {},
            },
        },
        keys = {
            {
                "<leader>/",
                function()
                    -- https://github.com/nvim-telescope/telescope-live-grep-args.nvim
                    -- Uses ripgrep args (rg) for live_grep
                    -- Command examples:
                    -- -i "Data"  # case insensitive
                    -- -g "!*.md" # ignore md files
                    -- -w # whole word
                    -- -e # regex
                    -- see 'man rg' for more
                    require("telescope").extensions.live_grep_args.live_grep_args() -- see arguments given in extensions config
                end,
                desc = "Live Grep (Args)",
            },
            -- change a keymap
            { "<leader><leader>", "<cmd>Telescope find_files<CR>", desc = "Find Files" },
            -- add a keymap to browse plugin files
            {
                "<leader>fp",
                function()
                    require("telescope.builtin").find_files({ cwd = require("lazy.core.config").options.root })
                end,
                desc = "Find Plugin File",
            },
            {
                "<C-p>",
                function()
                    require("telescope").extensions.projects.projects({ display_type = "full" })
                end,
                { noremap = true, desc = "Lookup project" },
            },
        },
    },
}
