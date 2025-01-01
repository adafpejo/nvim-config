return {
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "hrsh7th/cmp-cmdline",
            "hrsh7th/nvim-cmp",
            "WhoIsSethDaniel/mason-tool-installer.nvim",
            "saadparwaiz1/cmp_luasnip",
            "stevearc/conform.nvim",
            "j-hui/fidget.nvim",
            { "antosha417/nvim-lsp-file-operations", config = true },
        },
        config = function()
            -- used to enable autocompletion (assign to every lsp server config)
            -- local capabilities =
            --     vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), require("epo").register_cap())
            --

            require("conform").setup({
                formatters_by_ft = {},
            })

            local cmp = require("cmp")
            local cmp_lsp = require("cmp_nvim_lsp")
            local capabilities = vim.tbl_deep_extend(
                "force",
                {},
                vim.lsp.protocol.make_client_capabilities(),
                cmp_lsp.default_capabilities()
            )

            -- FIXME: workaround for https://github.com/neovim/neovim/issues/28058
            for _, v in pairs(capabilities) do
                if type(v) == "table" and v.workspace then
                    v.workspace.didChangeWatchedFiles = {
                        dynamicRegistration = false,
                        relativePatternSupport = false,
                    }
                end
            end

            -- https://github.com/nvimtools/none-ls.nvim/wiki/Avoiding-LSP-formatting-conflicts
            -- local lsp_formatting = function(bufnr)
            --     vim.lsp.buf.format({
            --         bufnr = bufnr,
            --     })
            -- end

            -- local augroup = vim.api.nvim_create_augroup("LspFormatting", {})

            -- local on_attach = function(client, bufnr)
            --     if client.supports_method("textDocument/formatting") then
            --         vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
            --         vim.api.nvim_create_autocmd("BufWritePre", {
            --             group = augroup,
            --             buffer = bufnr,
            --             callback = function()
            --                 lsp_formatting(bufnr)
            --             end,
            --         })
            --     end
            -- end

            require("fidget").setup({})
            -- configure mason
            require("mason").setup({})
            require("mason-lspconfig").setup({
                -- list of servers for mason to install
                ensure_installed = {
                    "tsserver",
                    "jsonls",
                    "eslint@4.8.0",
                    "html",
                    "cssls",
                    "tailwindcss",
                    "svelte",
                    "lua_ls",
                    "dockerls",
                    "prismals",
                    "gopls",
                    -- "graphql",
                    -- "emmet_ls",
                    "pyright",
                    "jdtls",
                    "java_language_server",
                    "kotlin_language_server",
                },
                -- auto-install configured servers (with lspconfig)
                automatic_installation = true, -- not the same as ensure_installed
                handlers = {
                    function(server_name) -- default handler (optional)
                        require("lspconfig")[server_name].setup({
                            capabilities = capabilities,
                            -- on_attach = on_attach,
                        })
                    end,
                    ["tsserver"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.tsserver.setup({
                            capabilities = capabilities,
                            -- on_attach = on_attach,
                            root_dir = function(...)
                                return require("lspconfig.util").root_pattern(".git")(...)
                            end,
                            -- on_attach = function(client)
                            --     client.server_capabilities.documentFormattingProvider = false
                            -- end,
                        })
                    end,
                    ["lua_ls"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.lua_ls.setup({
                            capabilities = capabilities,
                            settings = {
                                Lua = {
                                    runtime = { version = "Lua 5.1" },
                                    diagnostics = {
                                        globals = { "bit", "vim", "it", "describe", "before_each", "after_each" },
                                    },
                                },
                            },
                        })
                    end,
                    ["eslint"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.eslint.setup({
                            capabilities = capabilities,
                            -- on_attach = on_attach,
                            -- on_attach = function(client, bufnr)
                            --     client.server_capabilities.documentFormattingProvider = true
                            --     vim.api.nvim_create_autocmd("BufWritePre", {
                            --         pattern = { "*.tsx", "*.ts", "*.jsx", "*.js" },
                            --         command = "silent! EslintFixAll",
                            --     })
                            -- end,
                        })
                    end,
                },
            })

            require("mason-tool-installer").setup({
                ensure_installed = {
                    "prettier", -- prettier formatter
                    "prettierd", -- prettier formatter
                    "stylua", -- lua formatter
                    "isort", -- python formatter
                    "golangci-lint", -- golang linter
                    "black", -- python formatter
                    "pylint", -- python linter
                    "eslint_d", -- js linter
                },
            })
            --------

            cmp.setup({
                sources = cmp.config.sources({
                    { name = "nvim_lsp" },
                }, {
                    { name = "buffer" },
                }),
                mapping = cmp.mapping.preset.insert({
                    ["<C-k>"] = cmp.mapping.select_prev_item(cmp_select),
                    ["<C-j>"] = cmp.mapping.select_next_item(cmp_select),
                    ["<C-y>"] = cmp.mapping.confirm({ select = true }),
                    ["<C-Space>"] = cmp.mapping.complete(),
                }),
            })

            vim.diagnostic.config({
                -- update_in_insert = true,
                float = {
                    focusable = false,
                    style = "minimal",
                    border = "rounded",
                    source = "always",
                    header = "",
                    prefix = "",
                },
            })
        end,
    },
}
