local formatGoups = vim.api.nvim_create_augroup("autoFormat", {})

local function filterReactDTS(value)
    return string.match(value.filename, 'react/index.d.ts') == nil
end

local function filter(arr, fn)
    if type(arr) ~= "table" then
        return arr
    end

    local filtered = {}
    for k, v in pairs(arr) do
        if fn(v, k, arr) then
            table.insert(filtered, v)
        end
    end

    return filtered
end

local function on_list(options)
    -- [https://github.com/typescript-language-server/typescript-language-server/issues/216](https://github.com/typescript-language-server/typescript-language-server/issues/216)
    local items = options.items
    if #items > 1 then
        items = filter(items, filterReactDTS)
    end

    vim.fn.setqflist({}, ' ', { title = options.title, items = items, context = options.context })
    vim.api.nvim_command('cfirst')
end

return {
    {
        "neovim/nvim-lspconfig",
        event = { "BufReadPre", "BufNewFile" },
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            { "antosha417/nvim-lsp-file-operations", config = true },
        },
        config = function()
            -- import lspconfig plugin
            local lspconfig = require("lspconfig")

            -- get neotest namespace (api call creates or returns namespace)
            local lspconfig_ns = vim.api.nvim_create_namespace("lspconfig")
            vim.diagnostic.config({
                float = {
                    source = 'always',
                },
            }, lspconfig_ns)

            -- import cmp-nvim-lsp plugin
            local cmp_nvim_lsp = require("cmp_nvim_lsp")

            local keymap = vim.keymap -- for conciseness

            local opts = { noremap = true, silent = true }
            local on_attach = function(client, bufnr)
                opts.buffer = bufnr

                local utils = require('bsi.utils')

                if utils.has_value({ 'lua_ls', 'html', 'prettier', 'cssls', 'pyright' }, client.name) then
                    vim.api.nvim_clear_autocmds({ group = formatGoups, buffer = bufnr })
                    vim.api.nvim_create_autocmd("BufWritePre", {
                        group = formatGoups,
                        callback = function()
                            vim.lsp.buf.format()
                        end,
                    })
                end

                -- set keybinds
                opts.desc = "Show LSP references"
                keymap.set("n", "gr", "<cmd>Telescope lsp_references<CR>", opts) -- show definition, references

                opts.desc = "Go to declaration"
                keymap.set("n", "gD", function()
                    vim.lsp.buf.declaration({ on_list = on_list })
                end, opts) -- go to declaration

                opts.desc = "Show LSP definitions"
                keymap.set("n", "gd", function()
                    require("telescope.builtin").lsp_definitions()
                end, opts) -- show lsp definitions

                opts.desc = "Show LSP implementations"
                keymap.set("n", "gi", "<cmd>Telescope lsp_implementations<CR>", opts) -- show lsp implementations

                opts.desc = "Show LSP type definitions"
                keymap.set("n", "gt", "<cmd>Telescope lsp_type_definitions<CR>", opts) -- show lsp type definitions

                opts.desc = "See available code actions"
                keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts) -- see available code actions, in visual mode will apply to selection

                opts.desc = 'See all current buf actions'
                keymap.set("n", "<leader>cA", function()
                    vim.lsp.buf.code_action({
                        context = {
                            only = {
                                "source",
                            },
                            diagnostics = {},
                        },
                    })
                end, opts)

                opts.desc = "Lsp Info"
                keymap.set("n", "<leader>cl", "<cmd>LspInfo<CR>", opts)

                opts.desc = "Smart rename"
                keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts) -- smart rename

                opts.desc = "Show buffer diagnostics"
                keymap.set("n", "<leader>D", "<cmd>Telescope diagnostics bufnr=0<CR>", opts) -- show  diagnostics for file

                -- show diagnostics for line
                opts.desc = "Show line diagnostics"
                keymap.set("n", "<leader>d", function()
                    vim.diagnostic.open_float({ focusable = true })
                end, opts)

                opts.desc = "Go to previous diagnostic"
                keymap.set("n", "[d", vim.diagnostic.goto_prev, opts) -- jump to previous diagnostic in buffer

                opts.desc = "Go to next diagnostic"
                keymap.set("n", "]d", vim.diagnostic.goto_next, opts) -- jump to next diagnostic in buffer

                opts.desc = "Show documentation for what is under cursor"
                keymap.set("n", "D", vim.lsp.buf.hover, opts) -- show documentation for what is under cursor

                opts.desc = "Restart LSP"
                keymap.set("n", "<leader>rs", ":LspRestart<CR>", opts) -- mapping to restart lsp if necessary
            end

            -- used to enable autocompletion (assign to every lsp server config)
            local capabilities = cmp_nvim_lsp.default_capabilities()

            -- Change the Diagnostic symbols in the sign column (gutter)
            -- (not in youtube nvim video)
            local signs = { Error = " ", Warn = " ", Hint = "󰌵", Info = " " }
            for type, icon in pairs(signs) do
                local hl = "DiagnosticSign" .. type
                vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
            end

            -- configure html server
            lspconfig["html"].setup({
                capabilities = capabilities,
                on_attach = on_attach,
            })

            -- configure eslint server
            lspconfig["eslint"].setup({
                capabilities = capabilities,
                on_attach = function(client, bufnr)
                    on_attach(client, bufnr)
                    vim.api.nvim_create_autocmd("BufWritePre", {
                        pattern = { "*.tsx", "*.ts", "*.jsx", "*.js" },
                        command = "silent! EslintFixAll",
                        group = formatGoups,
                    })
                end,
            })

            -- configure typescript server with plugin
            lspconfig["tsserver"].setup({
                capabilities = capabilities,
                on_attach = on_attach,
            })

            -- configure css server
            lspconfig["cssls"].setup({
                capabilities = capabilities,
                on_attach = on_attach,
            })

            -- configure tailwindcss server
            lspconfig["tailwindcss"].setup({
                capabilities = capabilities,
                on_attach = on_attach,
            })

            -- configure svelte server
            lspconfig["svelte"].setup({
                capabilities = capabilities,
                on_attach = function(client, bufnr)
                    on_attach(client, bufnr)

                    vim.api.nvim_create_autocmd("BufWritePost", {
                        pattern = { "*.js", "*.ts" },
                        callback = function(ctx)
                            if client.name == "svelte" then
                                client.notify("$/onDidChangeTsOrJsFile", { uri = ctx.file })
                            end
                        end,
                    })
                end,
            })

            -- configure prisma orm server
            lspconfig["prismals"].setup({
                capabilities = capabilities,
                on_attach = on_attach,
            })

            -- configure graphql language server
            lspconfig["graphql"].setup({
                capabilities = capabilities,
                on_attach = on_attach,
                filetypes = { "graphql", "gql", "svelte", "typescriptreact", "javascriptreact" },
            })

            -- configure emmet language server
            lspconfig["emmet_ls"].setup({
                capabilities = capabilities,
                on_attach = on_attach,
                filetypes = { "html", "typescriptreact", "javascriptreact", "css", "sass", "scss", "less", "svelte" },
            })

            -- configure python server
            lspconfig["pyright"].setup({
                capabilities = capabilities,
                on_attach = on_attach,
            })

            -- configure lua server (with special settings)
            lspconfig["lua_ls"].setup({
                capabilities = capabilities,
                on_attach = on_attach,

                settings = { -- custom settings for lua
                    Lua = {
                        -- make the language server recognize "vim" global
                        diagnostics = {
                            globals = { "vim" },
                        },
                        workspace = {
                            -- make language server aware of runtime files
                            library = {
                                [vim.fn.expand("$VIMRUNTIME/lua")] = true,
                                [vim.fn.stdpath("config") .. "/lua"] = true,
                            },
                        },
                    },
                },
            })
        end,
    },
}
