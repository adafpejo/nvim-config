return {
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            { "mason-org/mason.nvim",           version = "1.11.0" },
            { "mason-org/mason-lspconfig.nvim", version = "1.32.0" },
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "hrsh7th/cmp-cmdline",
            "hrsh7th/nvim-cmp",
            "WhoIsSethDaniel/mason-tool-installer.nvim",
            "saadparwaiz1/cmp_luasnip",
            -- "stevearc/conform.nvim",
            "j-hui/fidget.nvim",
            { "antosha417/nvim-lsp-file-operations", config = true },
        },
        config = function()
            -- used to enable autocompletion (assign to every lsp server config)
            -- local capabilities =
            --     vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), require("epo").register_cap())
            --

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
                    "ts_ls",
                    "rescriptls",
                    "helm_ls",
                    "jsonls",
                    "yamlls",
                    "eslint@4.8.0",
                    "html",
                    "cssls",
                    "tailwindcss",
                    "svelte",
                    "gopls@1.24.0",
                    "lua_ls",
                    "dockerls",
                    "prismals",
                    "terraformls",
                    -- "graphql",
                    -- "emmet_ls",
                    "pyright",
                    "jdtls",
                    "java_language_server",
                    "kotlin_language_server",
                },
                -- auto-install configured servers (with lspconfig)
                automatic_installation = true, -- not the same as ensure_installed
                automatic_enable = false,
                handlers = {
                    function(server_name) -- default handler (optional)
                        require("lspconfig")[server_name].setup({
                            capabilities = capabilities,
                            flags = {
                                debounce_text_changing = 150
                            }
                            -- on_attach = on_attach,
                        })
                    end,
                    ["pyright"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.pyright.setup({
                            settings = {
                                python = {
                                    pythonPath = "/env/bin/python",
                                    venvPath = ".",
                                    venv = "env"
                                }
                            }
                        })
                    end,
                    ["rescriptls"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.helm_ls.setup({})
                    end,
                    ["yamlls"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.yamlls.setup({
                            filetypes = { "yaml" },
                        })
                    end,
                    ["helm_ls"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.helm_ls.setup({
                            filetypes = { "helm" }
                        })
                    end,
                    ["ts_ls"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.ts_ls.setup({
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
                                    runtime = {
                                        version = 'LuaJIT', -- Neovim uses LuaJIT
                                    },
                                    workspace = {
                                        library = vim.api.nvim_get_runtime_file("", true), -- Include Neovim runtime files
                                    },
                                    telemetry = { enable = false }, -- Optional: disable telemetry,
                                },
                            }
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
                    ["dartls"] = function()
                        require("lspconfig").dartls.setup({
                            capabilities = capabilities,
                            filetypes = { "dart" },
                            cmd = { "dart", "language-server", "--protocol=lsp" }
                        })
                    end
                },
            })

            require("mason-tool-installer").setup({
                ensure_installed = {
                    "prettier",      -- prettier formatter
                    "prettierd",     -- prettier formatter
                    "stylua",        -- lua formatter
                    "isort",         -- python formatter
                    "golangci-lint", -- golang linter
                    "black",         -- python formatter
                    "pylint",        -- python linter
                    "eslint_d",      -- js linter
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
