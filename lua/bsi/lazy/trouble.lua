return {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
        {
            "<leader>xx",
            function()
                require("trouble").toggle()
            end,
        },
        {
            "<leader>xw",
            function()
                require("trouble").toggle("workspace_diagnostics")
            end,
            { desc = "toggle(workspace_diagnostics)" },
        },
        {
            "<leader>xd",
            function()
                require("trouble").toggle("document_diagnostics")
            end,
            { desc = "toggle(document_diagnostics)" },
        },
        {
            "<leader>xq",
            function()
                require("trouble").toggle("quickfix")
            end,
            { desc = "toggle(quickfix)" },
        },
        {
            "<leader>xl",
            function()
                require("trouble").toggle("loclist")
            end,
            { desc = "toggle(loclist)" },
        },
        {
            "gR",
            function()
                require("trouble").toggle("lsp_references")
            end,
            { desc = "toggle(lsp_references)" },
        },
    },
}
