-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vim.keymap.set("n", "<C-/>", "<cmd>ToggleTermToggleAll<CR>")

vim.g.mapleader = " "

local copilot_on = true
vim.api.nvim_create_user_command("CopilotToggle", function()
    if copilot_on then
        vim.cmd("Copilot disable")
    else
        vim.cmd("Copilot enable")
    end
    copilot_on = not copilot_on
end, { nargs = 0 })

vim.keymap.set("n", "<leader>ct", function()
    vim.cmd("CopilotToggle")
end, { noremap = true, desc = "Toggle Copilot" })

vim.keymap.set("n", "<leader>cg", function()
    vim.cmd("ChatGPT")
end, { noremap = true, desc = "ChatGpt" })

-- exit insert mode with jk
vim.keymap.set("i", "jk", "<ESC>", { noremap = true, silent = true, desc = "<ESC>" })

-- Perusing code faster with K and J
vim.keymap.set({ "n", "v" }, "K", "5k", { noremap = true, desc = "Up faster" })
vim.keymap.set({ "n", "v" }, "J", "5j", { noremap = true, desc = "Down faster" })

-- Remap K and J
vim.keymap.set({ "n", "v" }, "<leader>k", "K", { noremap = true, desc = "Keyword" })
vim.keymap.set({ "n", "v" }, "<leader>j", "J", { noremap = true, desc = "Join lines" })

-- C-P classic
vim.keymap.set("n", "<C-P>", "<leader>ff")

-- Save file
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { noremap = true, desc = "Save window" })

-- Quike exit
vim.keymap.set("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quike quite" })

vim.keymap.set("n", "<leader>L", "<cmd>Lazy<cr>", { desc = ":Lazy" })
vim.keymap.set("n", "<leader>vd", "<cmd>noh<cr>", { desc = "Remove visual" })

-- Devdocs
vim.keymap.set("n", "<leader>dd", "<cmd>DevdocsOpen<cr>", { noremap = true, desc = "Open Devdocs" })

-- Lazygit
vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { noremap = true, desc = "Open lazygit" })

-- Spectrume
vim.keymap.set('n', '<leader>S', '<cmd>lua require("spectre").toggle()<CR>', {
    desc = "Toggle Spectre"
})
vim.keymap.set('n', '<leader>sw', '<cmd>lua require("spectre").open_visual({select_word=true})<CR>', {
    desc = "Search current word"
})
vim.keymap.set('v', '<leader>sw', '<esc><cmd>lua require("spectre").open_visual()<CR>', {
    desc = "Search current word"
})
vim.keymap.set('n', '<leader>sp', '<cmd>lua require("spectre").open_file_search({select_word=true})<CR>', {
    desc = "Search on current file"
})

vim.keymap.set("n", "<leader>sw", function()
    -- Get the word under the cursor
    local word = vim.fn.expand("<cword>")

    SearchGoogle(word)
end, { desc = "Search word under cur" })

-- Function to get the visual selection
local function get_visual_selection()
    -- Get the start and end positions of the visual selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    -- Get the line numbers and columns
    local line_start = start_pos[2]
    local column_start = start_pos[3]
    local line_end = end_pos[2]
    local column_end = end_pos[3]

    -- Extract the selected lines
    local lines = vim.fn.getline(line_start, line_end)
    if #lines == 0 then return '' end

    -- Adjust the first and last lines to the selection
    lines[1] = lines[1]:sub(column_start, -1)
    lines[#lines] = lines[#lines]:sub(1, column_end)

    return table.concat(lines, " ")
end

-- Function to URL encode a string
local function url_encode(str)
    if str then
        str = str:gsub("\n", " "):gsub("([^%w %-%_%.%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = str:gsub(" ", "%%20")
    end
    return str
end

vim.keymap.set("v", "<leader>si", function()
    -- Get the selected text in visual mode
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    -- Extract the selected text
    local lines = get_visual_selection()
    local encodedlines = url_encode(lines)
    SearchGoogle(encodedlines)
end, { desc = "Search selected block" })

vim.keymap.set('n', '<D-s>', ':w<CR>', { noremap = true, silent = true })
-- Map Cmd+S to save in insert mode
vim.keymap.set('i', '<D-s>', '<Esc>:w<CR>', { noremap = true, silent = true })

-- Create a custom command to reload the init.lua file
vim.cmd [[
      command! ReloadConfig lua require('user_config').reload_config()
    ]]

-- Map Cmd+R to the ReloadConfig command
-- vim.api.nvim_set_keymap('n', '<D-r>', ':ReloadConfig<CR>', { noremap = true })

-- Unmap mappings used by tmux plugin
-- TODO(vintharas): There's likely a better way to do this.
-- vim.keymap.del("n", "<C-h>")
-- vim.keymap.del("n", "<C-j>")
-- vim.keymap.del("n", "<C-k>")
-- vim.keymap.del("n", "<C-l>")
-- vim.keymap.set("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>")
-- vim.keymap.set("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>")
-- vim.keymap.set("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>")
-- vim.keymap.set("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>")
