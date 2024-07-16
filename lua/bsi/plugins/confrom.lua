return {
    {
        "stevearc/conform.nvim",
        config = function ()
            require('conform').setup({
                -- formatters = {
                    -- Defining Prettier as a formatter
                    -- prettier = {
                    --     command = "prettier",                                                                -- Ensure Prettier is installed and accessible
                    --     args = { "--config", "~/.config/nvim/.prettierrc", "--stdin-filepath", "$FILENAME" }, -- Path to your default Prettier config
                    --     root_markers = { ".git" },                                                           -- Determines project root; can adjust as needed
                    -- },
                -- },
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
                    ["yaml"] = { "prettierd" },
                    ["markdown"] = { "prettierd" },
                    ["markdown.mdx"] = { "prettierd" },
                    ["graphql"] = { "prettierd" },
                    ["handlebars"] = { "prettierd" },
                },
            })

            vim.api.nvim_create_autocmd("BufWritePre", {
              pattern = "*",
              callback = function(args)
                require("conform").format({ bufnr = args.buf })
              end,
            })
        end
    },
}
