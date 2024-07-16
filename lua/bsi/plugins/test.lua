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
            -- default an require deps
            "nvim-neotest/nvim-nio",
            "nvim-lua/plenary.nvim",
            "antoinemadec/FixCursorHold.nvim",
            "nvim-treesitter/nvim-treesitter",
            ------

            { "vim-test/vim-test" },
            { "nvim-neotest/neotest-jest" },
            { "marilari88/neotest-vitest" },
            { "thenbe/neotest-playwright" },

            -- adapters
            { "nvim-neotest/neotest-go",  commit = "05535cb2cfe3ce5c960f65784896d40109572f89" }, -- https://github.com/nvim-neotest/neotest-go/issues/57
            { 'rcasia/neotest-java' },
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
                "<leader>tu",
                function()
                    require("neotest").run.run({ path = vim.fn.expand("%"), extra_args = { "-u" } })
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
                ["neotest-jest"] = {
                    cwd = function()
                        return vim.fn.getcwd()
                    end,
                },
                ["neotest-vitest"] = {
                },
                ["neotest-java"] = {
                    filetypes = { "java", "kotlin" },
                    junit_jar = "~/.config/tools/unit-platform-console-standalone-1.10.2.jar",
                }
            },
        },
        config = function(_, opts)
            local neotest_ns = vim.api.nvim_create_namespace("neotest")
            vim.diagnostic.config({
                virtual_text = {
                    format = function(diagnostic)
                        -- Replace newline and tab characters with space for more compact diagnostics
                        local message = diagnostic.message:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+",
                            "")
                        return message
                    end,
                },
            }, neotest_ns)

            if opts.adapters then
                local adapters = {}
                for name, config in pairs(opts.adapters or {}) do
                    if type(name) == "number" then
                        if type(config) == "string" then
                            config = require(config)
                        end
                        adapters[#adapters + 1] = config
                    elseif config ~= false then
                        local adapter = require(name)
                        if type(config) == "table" and not vim.tbl_isempty(config) then
                            local meta = getmetatable(adapter)
                            if adapter.setup then
                                adapter.setup(config)
                            elseif adapter.adapter then
                                adapter.adapter(config)
                                adapter = adapter.adapter
                            elseif meta and meta.__call then
                                adapter(config)
                            else
                                error("Adapter " .. name .. " does not support setup")
                            end
                        end
                        adapters[#adapters + 1] = adapter
                    end
                end
                opts.adapters = adapters
            end

            require("neotest").setup(opts)
        end,
    },

    {
        "andythigpen/nvim-coverage",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<leader>tc", "<cmd>Coverage<cr>",                             desc = "Coverage in gutter" },
            { "<leader>tC", "<cmd>CoverageLoad<cr><cmd>CoverageSummary<cr>", desc = "Coverage summary" },
        },
        config = function()
            require("coverage").setup({
                auto_reload = true,
                lang = {
                    javascript = {
                        coverage_file = '.coverage/lcov.info'
                    }
                }
            })
        end,
    },
}
