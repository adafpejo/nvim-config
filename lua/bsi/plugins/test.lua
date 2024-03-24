return {
    {
        "folke/which-key.nvim",
        optional = true,
        opts = {
            defaults = {
                ["<leader>t"] = { name = "+test" },
            },
        },
    },
    {
        "nvim-neotest/neotest",

        dependencies = {
            { "nvim-lua/plenary.nvim" },
            { "nvim-treesitter/nvim-treesitter" },
            { "antoinemadec/FixCursorHold.nvim" },
            { "folke/neodev.nvim" },

            { "haydenmeade/neotest-jest" },
            { "marilari88/neotest-vitest" },
            { "thenbe/neotest-playwright" },

            -- adapters
            { "nvim-neotest/neotest-vim-test" },
            { "nvim-neotest/neotest-python" },
            { "rouge8/neotest-rust" },
            { "nvim-neotest/neotest-go", commit = "05535cb2cfe3ce5c960f65784896d40109572f89" }, -- https://github.com/nvim-neotest/neotest-go/issues/57
            { "vim-test/vim-test" },
        },

        keys = {
            {
                "<leader>tS",
                ":lua require('neotest').run.run({ suite = true })<CR>",
                desc = "Run all tests in suite",
            },
            {
                "<leader>tt",
                function()
                    require("neotest").run.run(vim.fn.expand("%"))
                end,
                desc = "Run File",
            },
            {
                "<leader>tT",
                function()
                    require("neotest").run.run(vim.loop.cwd())
                end,
                desc = "Run All Test Files",
            },
            {
                "<leader>tr",
                function()
                    require("neotest").run.run()
                end,
                desc = "Run Nearest",
            },
            {
                "<leader>tl",
                function()
                    require("neotest").run.run_last()
                end,
                desc = "Run Last",
            },
            {
                "<leader>ts",
                function()
                    require("neotest").summary.toggle()
                end,
                desc = "Toggle Summary",
            },
            {
                "<leader>to",
                function()
                    require("neotest").output.open({ enter = true, auto_close = true })
                end,
                desc = "Show Output",
            },
            {
                "<leader>tO",
                function()
                    require("neotest").output_panel.toggle()
                end,
                desc = "Toggle Output Panel",
            },
            {
                "<leader>tS",
                function()
                    require("neotest").run.stop()
                end,
                desc = "Stop",
            },
        },

        opts = {
            adapters = {
                ["neotest-python"] = {
                    -- https://github.com/nvim-neotest/neotest-python
                    runner = "pytest",
                    args = { "--log-level", "INFO", "--color", "yes", "-vv", "-s" },
                    -- dap = { justMyCode = false },
                },
                ["neotest-go"] = {
                    args = { "-coverprofile=coverage.out" },
                },
                ["neotest-playwright"] = {
                    options = {
                        preset = "headed",
                        enable_dynamic_test_discovery = true,
                        get_playwright_binary = function()
                            return vim.loop.cwd() + "/node_modules/.bin/playwright"
                        end,
                        get_playwright_config = function()
                            return vim.loop.cwd() + "/playwright.config.ts"
                        end,
                    },
                },
                -- ["neotest-rust"] = {
                --   -- see lazy.lua
                --   -- https://github.com/rouge8/neotest-rust
                --   --
                --   -- requires nextest, which can be installed via "cargo binstall":
                --   -- https://github.com/cargo-bins/cargo-binstall
                --   -- https://nexte.st/book/pre-built-binaries.html
                -- },
                ["neotest-vim-test"] = {
                    -- https://github.com/nvim-neotest/neotest-vim-test
                    ignore_file_types = { "python", "vim", "lua", "rust", "go" },
                },
                ["neotest-jest"] = {
                    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
                    jestCommand = "npm test --",
                    cwd = function()
                        return vim.fn.getcwd()
                    end,
                },
            },
        },
    },

    {
        "andythigpen/nvim-coverage",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<leader>tc", "<cmd>Coverage<cr>", desc = "Coverage in gutter" },
            { "<leader>tC", "<cmd>CoverageLoad<cr><cmd>CoverageSummary<cr>", desc = "Coverage summary" },
        },
        config = function()
            require("coverage").setup({
                auto_reload = true,
            })
        end,
    },
}
