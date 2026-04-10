require("telescope").setup({
    defaults = {
        file_ignore_patterns = { ".git/", "node_modules", "poetry.lock" },
        vimgrep_arguments = {
            "rg",
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
            "--smart-case",
            "--hidden",
        },
        layout_strategy = "flex",
        layout_config = {
            horizontal = {
                preview_width = 0.5,
            },
            vertical = {
                preview_height = 0.5,
            },
            width = 0.99,
            height = 0.99,
        },
        mappings = {
          i = {
            ["<C-q>"] = require("telescope.actions").send_to_qflist + require("telescope.actions").open_qflist,
            ["<M-q>"] = require("telescope.actions").send_selected_to_qflist + require("telescope.actions").open_qflist,
          },
          n = {
            ["<C-q>"] = require("telescope.actions").send_to_qflist + require("telescope.actions").open_qflist,
            ["<M-q>"] = require("telescope.actions").send_selected_to_qflist + require("telescope.actions").open_qflist,
          },
        },
    }
})

