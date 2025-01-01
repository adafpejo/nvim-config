return {
    {
        "stevearc/conform.nvim",
        config = function()
            require("conform").setup({
                notify_on_error = false,
                formatters_by_ft = {
                    ["lua"] = { "stylua" },
                    ["javascript"] = { "eslint_d", "prettierd" },
                    ["javascriptreact"] = { "eslint_d", "prettierd" },
                    ["typescript"] = { "eslint_d", "prettierd" },
                    ["typescriptreact"] = { "eslint_d", "prettierd" },
                    ["vue"] = { "prettierd" },
                    ["css"] = { "prettierd" },
                    ["scss"] = { "prettierd" },
                    ["less"] = { "prettierd" },
                    ["html"] = { "prettierd" },
                    ["json"] = { "prettierd" },
                    ["jsonc"] = { "prettierd" },
                    ["markdown"] = { "prettierd" },
                    ["markdown.mdx"] = { "prettierd" },
                    ["graphql"] = { "prettierd" },
                    ["handlebars"] = { "prettierd" },
                    -- Use the "*" filetype to run formatters on all filetypes.
                    ["*"] = { "codespell" },
                },
            })

            local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
            vim.api.nvim_create_autocmd("BufWritePre", {
                pattern = "*",
                group = augroup,
                callback = function(args)
                    require("conform").format({ bufnr = args.buf })
                end,
            })
            vim.api.nvim_create_autocmd("BufWritePre", {
                pattern = { "*.js", "*.ts", "*.tsx", "*.jsx" },
                group = augroup,
                callback = function()
                    vim.cmd("silent! EslintFixAll")
                end,
            })
        end,
    },
}
