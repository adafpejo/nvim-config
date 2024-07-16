local formatGroups = vim.api.nvim_create_augroup("autoFormat", {})

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

local tsHandlers = {
    ["textDocument/definition"] = function(_, result, params)
        local util = require("vim.lsp.util")
        if result == nil or vim.tbl_isempty(result) then
            -- local _ = vim.lsp.log.info() and vim.lsp.log.info(params.method, "No location found")
            return nil
        end

        if vim.tbl_islist(result) then
            util.jump_to_location(result[1])

            if #result > 1 then
                local isReactDTs = false
                ---@diagnostic disable-next-line: unused-local
                for key, value in pairs(result) do
                    if string.match(value.uri, "react/index.d.ts") then
                        isReactDTs = true
                        break
                    end
                end
                if not isReactDTs then
                    util.set_qflist(util.locations_to_items(result))
                    vim.api.nvim_command("copen")
                    vim.api.nvim_command("wincmd p")
                end
            end
        else
            util.jump_to_location(result)
        end
    end,
}

return {
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "nvimdev/epo.nvim",
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "WhoIsSethDaniel/mason-tool-installer.nvim",
            "j-hui/fidget.nvim",
            { "antosha417/nvim-lsp-file-operations", config = true },
        },
        config = function()
            -- used to enable autocompletion (assign to every lsp server config)
            local capabilities = vim.tbl_deep_extend('force',
                vim.lsp.protocol.make_client_capabilities(),
                require('epo').register_cap()
            )

            require("fidget").setup({})
            -- configure mason
            require("mason").setup({})
            require("mason-lspconfig").setup({
                -- list of servers for mason to install
                ensure_installed = {
                    "tsserver",
                    "jsonls",
                    "eslint",
                    "html",
                    "cssls",
                    "tailwindcss",
                    "svelte",
                    "lua_ls",
                    "prettierd",
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
                    function(server_name)      -- default handler (optional)
                        require("lspconfig")[server_name].setup {
                            capabilities = capabilities
                        }
                    end,
                    ["lua_ls"] = function()
                        local lspconfig = require("lspconfig")
                        lspconfig.lua_ls.setup {
                            capabilities = capabilities,
                            settings = {
                                Lua = {
                                    runtime = { version = "Lua 5.1" },
                                    diagnostics = {
                                        globals = { "bit", "vim", "it", "describe", "before_each", "after_each" },
                                    }
                                }
                            }
                        }
                    end,
                 }
            })

            require('mason-tool-installer').setup({
                ensure_installed = {
                    "prettier", -- prettier formatter
                    "stylua",   -- lua formatter
                    "isort",    -- python formatter
                    "black",    -- python formatter
                    "pylint",   -- python linter
                    "eslint_d", -- js linter
                },
            })
            --------

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
