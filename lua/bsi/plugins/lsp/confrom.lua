return {
    {
        "stevearc/conform.nvim",
        optional = true,
        opts = {
            formatters = {
                -- Defining Prettier as a formatter
                prettier = {
                    command = "prettier",                                                                -- Ensure Prettier is installed and accessible
                    args = { "--config", "~/config/nvim/.prettierrc", "--stdin-filepath", "$FILENAME" }, -- Path to your default Prettier config
                    root_markers = { ".git" },                                                           -- Determines project root; can adjust as needed
                },
            },
            formatters_by_ft = {
                ["lua"] = { "stylua" },
                ["javascript"] = { "prettier" },
                ["javascriptreact"] = { "prettier" },
                ["typescript"] = { "prettier" },
                ["typescriptreact"] = { "prettier" },
                ["vue"] = { "prettier" },
                ["css"] = { "prettier" },
                ["scss"] = { "prettier" },
                ["less"] = { "prettier" },
                ["html"] = { "prettier" },
                ["json"] = { "prettier" },
                ["jsonc"] = { "prettier" },
                ["yaml"] = { "prettier" },
                ["markdown"] = { "prettier" },
                ["markdown.mdx"] = { "prettier" },
                ["graphql"] = { "prettier" },
                ["handlebars"] = { "prettier" },
            },
        },
    },
}
