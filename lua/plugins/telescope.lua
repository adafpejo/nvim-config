local nvim = require('bsi.utils.nvim')

return {
    -- change telescope config
    {
        "nvim-telescope/telescope.nvim",
        lazy = false,
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
                    "-g",
                    "!{.git,node_modules}/*",
                },
            },
            pickers = {
                find_files = {
                    find_command = { "rg", "--files", "--hidden", "-g", "!{.git,node_modules}/*", "-g", ".*" },
                },
            },
        },
        config = function()
            require("telescope").setup({
                defaults = {
                    vimgrep_arguments = {
                        "rg",
                        "--color=never",
                        "--no-heading",
                        "--with-filename",
                        "--line-number",
                        "--column",
                        "--smart-case",
                        "--hidden",
                    },
                },
            })
            -- set keymaps
            local keymap = vim.keymap -- for conciseness
            keymap.set("n", "<leader><leader>", "<cmd>Telescope find_files<cr>", { desc = "Fuzzy find files in cwd" })
            keymap.set("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Fuzzy find recent files" })
            keymap.set("n", "<leader>fs", "<cmd>Telescope live_grep<cr>", { desc = "Find string in cwd" })
            keymap.set("n", "<leader>p", "<cmd>Telescope projects<cr>", { desc = "Projects list" })
            keymap.set("n", "<leader>fg", ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>", { desc = "Find string in cwd" })
            keymap.set("n", "<leader>fw", function()
                local word = nvim.get_cursor_word()

                require("telescope.builtin").live_grep({
                    default_text = word,
                })

                local timer = vim.loop.new_timer()

                -- timeout to wait telescope result
                timer:start(
                    50,
                    0,
                    vim.schedule_wrap(function()
                        vim.cmd("stopinsert")
                    end)
                )
            end, { desc = "Find string in cwd" })
            keymap.set(
                "n",
                "<leader>fc",
                "<cmd>Telescope grep_string<cr>",
                { desc = "Find string under cursor in cwd" }
            )
        end,
    },
}
