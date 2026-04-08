local actions = require("diffview.actions")
require('diffview').setup({
    file_history_view = 'list',
    keymaps = {
        file_panel = {
            { "n", "j", function()
                actions.next_entry()
                actions.select_entry()
            end, { desc = "Bring the cursor to the next file entry" } },
            { "n", "k", function()
                actions.prev_entry()
                actions.select_entry()
            end, { desc = "Bring the cursor to the previous file entry" } },
        },
        file_history_view = {
            { "n", "<C-j>", function()
                actions.next_entry()
                actions.select_entry()
            end, { desc = "Bring the cursor to the next file entry" } },
            { "n", "<C-k>", function()
                actions.prev_entry()
                actions.select_entry()
            end, { desc = "Bring the cursor to the previous file entry" } },
            { "n", "j", function()
                actions.scroll_view(1)
            end, { desc = "Bring the cursor to the next file entry" } },
            { "n", "k", function()
                actions.scroll_view(-1)
            end, { desc = "Bring the cursor to the previous file entry" } },
           { "n", "J", function()
                actions.scroll_view(5)
            end, { desc = "Bring the cursor to the next file entry" } },
            { "n", "K", function()
                actions.scroll_view(-5)
            end, { desc = "Bring the cursor to the previous file entry" } },

        }
    }
})

