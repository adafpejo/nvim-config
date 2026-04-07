local nvim = require('bsi.utils.nvim')

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
    },
})

-- set keymaps
local keymap = vim.keymap             -- for conciseness
keymap.set("n", "<leader><leader>", "<cmd>Telescope find_files<cr>", { desc = "Fuzzy find files in cwd" })
keymap.set("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Fuzzy find recent files" })
keymap.set("n", "<leader>fs", "<cmd>Telescope live_grep<cr>", { desc = "Find string in cwd" })
keymap.set("n", "<leader>p", "<cmd>Telescope projects<cr>", { desc = "Projects list" })
keymap.set("n", "<leader>fg", ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>",
    { desc = "Find string in cwd" })
keymap.set("n", "<leader>fw", function()
    local word = nvim.get_cursor_word()

    require("telescope.builtin").live_grep({
        default_text = word,
    })

    local timer = vim.loop.new_timer()

    -- timeout to wait telescope result
    timer:start(
        50,
        0,
        vim.schedule_wrap(function()
            vim.cmd("stopinsert")
        end)
    )
end, { desc = "Find string in cwd" })
keymap.set(
    "n",
    "<leader>fc",
    "<cmd>Telescope grep_string<cr>",
    { desc = "Find string under cursor in cwd" }
)
