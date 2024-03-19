local get_root_dir = function(fname)
    local util = require("lspconfig.util")
    return util.root_pattern(".git")(fname) or util.root_pattern("package.json", "tsconfig.json")(fname)
end

return {
    -- add typescript to treesitter
    {
        "nvim-treesitter/nvim-treesitter",
        opts = function(_, opts)
            if type(opts.ensure_installed) == "table" then
                vim.list_extend(opts.ensure_installed, { "typescript", "tsx" })
            end
        end,
    },
    -- correctly setup lspconfig
    {
        "neovim/nvim-lspconfig",
        opts = {
            -- make sure mason installs the server
            servers = {
                eslint = {
                    root_dir = get_root_dir,
                },
                tsserver = {
                    path = "",
                    root_dir = get_root_dir,
                    single_file_support = false,
                    settings = {
                        typescript = {
                            inlayHints = {
                                includeInlayParameterNameHints = "literal",
                                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                                includeInlayFunctionParameterTypeHints = true,
                                includeInlayVariableTypeHints = false,
                                includeInlayPropertyDeclarationTypeHints = true,
                                includeInlayFunctionLikeReturnTypeHints = true,
                                includeInlayEnumMemberValueHints = true,
                            },
                        },
                        javascript = {
                            inlayHints = {
                                includeInlayParameterNameHints = "all",
                                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                                includeInlayFunctionParameterTypeHints = true,
                                includeInlayVariableTypeHints = true,
                                includeInlayPropertyDeclarationTypeHints = true,
                                includeInlayFunctionLikeReturnTypeHints = true,
                                includeInlayEnumMemberValueHints = true,
                            },
                        },
                        completions = {
                            completeFunctionCalls = true,
                        },
                    },
                    keys = {
                        {
                            "<leader>co",
                            function()
                                vim.lsp.buf.code_action({
                                    apply = true,
                                    context = {
                                        only = { "source.organizeimports.ts" },
                                        diagnostics = {},
                                    },
                                })
                            end,
                            desc = "organize imports",
                        },
                        {
                            "<leader>cR",
                            function()
                                vim.lsp.buf.code_action({
                                    apply = true,
                                    context = {
                                        only = { "source.removeunused.ts" },
                                        diagnostics = {},
                                    },
                                })
                            end,
                            desc = "remove unused imports",
                        },
                    },
                },
            },
        },
    },
    {
        "mfussenegger/nvim-dap",
        optional = true,
        dependencies = {
            {
                "williamboman/mason.nvim",
                opts = function(_, opts)
                    opts.ensure_installed = opts.ensure_installed or {}
                    table.insert(opts.ensure_installed, "js-debug-adapter")
                end,
            },
        },
        opts = function()
            local dap = require("dap")
            if not dap.adapters["pwa-node"] then
                require("dap").adapters["pwa-node"] = {
                    type = "server",
                    host = "localhost",
                    port = "${port}",
                    executable = {
                        command = "node",
                        -- 💀 make sure to update this path to point to your installation
                        args = {
                            require("mason-registry").get_package("js-debug-adapter"):get_install_path()
                                .. "/js-debug/src/dapdebugserver.js",
                            "${port}",
                        },
                    },
                }
            end
            for _, language in ipairs({ "typescript", "javascript", "typescriptreact", "javascriptreact" }) do
                if not dap.configurations[language] then
                    dap.configurations[language] = {
                        {
                            type = "pwa-node",
                            request = "launch",
                            name = "launch file",
                            program = "${file}",
                            cwd = "${workspacefolder}",
                        },
                        {
                            type = "pwa-node",
                            request = "attach",
                            name = "attach",
                            processid = require("dap.utils").pick_process,
                            cwd = "${workspacefolder}",
                        },
                    }
                end
            end
        end,
    },
}
