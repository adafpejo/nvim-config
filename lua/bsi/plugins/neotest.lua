return {
    {
        "folke/which-key.nvim",
    },
    {
        "nvim-neotest/neotest",
        dependencies = {
            "nvim-neotest/nvim-nio",
            "nvim-lua/plenary.nvim",
            "antoinemadec/FixCursorHold.nvim",
            "nvim-treesitter/nvim-treesitter",
            "nvim-neotest/neotest-jest",
            -- "marilari88/neotest-vitest",
            -- "Issafalcon/neotest-dotnet",
            -- "nvim-neotest/neotest-go",
            -- "thenbe/neotest-playwright"
        },
        config = function()
            -- get neotest namespace (api call creates or returns namespace)
            local neotest_ns = vim.api.nvim_create_namespace("neotest")
            vim.diagnostic.config({
                virtual_text = {
                    format = function(diagnostic)
                        local message =
                            diagnostic.message:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+", "")
                        return message
                    end,
                },
            }, neotest_ns)

            -- setup keybindings
            vim.keymap.set("n", "<leader>tt", function()
                    vim.api.nvim_command('write')
                    require("neotest").run.run(vim.fn.expand("%"))
                end,
                { desc = "Run File" })

            vim.keymap.set("n", "<leader>tT", function()
                    vim.api.nvim_command('write')
                    require("neotest").run.run(vim.uv.cwd())
                end,
                { desc = "Run All Test Files" })
            vim.keymap.set("n", "<leader>tr", function()
                vim.api.nvim_command('write')
                require("neotest").run.run()
            end, { desc = "Run Nearest" })
            vim.keymap.set("n", "<leader>tl", function() require("neotest").run.run_last() end, { desc = "Run Last" })
            vim.keymap.set("n", "<leader>ts", function() require("neotest").summary.toggle() end,
                { desc = "Toggle Summary" })
            vim.keymap.set("n", "<leader>to",
                function() require("neotest").output.open({ enter = true, auto_close = true }) end,
                { desc = "Show Output" })
            vim.keymap.set("n", "<leader>tO", function() require("neotest").output_panel.toggle() end,
                { desc = "Toggle Output Panel" })
            vim.keymap.set("n", "<leader>tS", function() require("neotest").run.stop() end, { desc = "Stop" })

            require("neotest").setup({
                discovery = {
                    filter_dir = function(dir)
                        return not vim.startswith(dir, "node_modules")
                    end,
                },
                icons = {
                    running_animated = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
                },
                adapters = {
                    -- require("neotest-dotnet"),
                    -- require("neotest-go"),
                    require("neotest-jest")({
                        jestCommand = "npm test --",
                        cwd = function(path)
                            return vim.fn.getcwd()
                        end,
                    }),
                    -- require("neotest-playwright"),
                }
            })
        end,
    },
}
