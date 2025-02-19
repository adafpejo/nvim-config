local dx = require("bsi.dx")
local refactoring = require("bsi.refactoring")
local nvim = require("bsi.utils.nvim")
local ai = require("bsi.ai")
local nvim_tree_api = require("nvim-tree.api")
local webify        = require("bsi.webify")

-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vim.keymap.set("n", "<C-/>", "<cmd>ToggleTermToggleAll<CR>")

-- exit insert mode with jk
vim.keymap.set("i", "jk", "<ESC>", { noremap = true, silent = true, desc = "<ESC>" })

-- files navigation
vim.keymap.set({ "n" }, "<C-j>", function()
    vim.cmd("TmuxNavigateLeft")
    nvim.move_cursor_down()
    nvim_tree_api.node.open.edit()
end, { noremap = true, desc = "Open next file" })
vim.keymap.set({ "n" }, "<C-k>", function()
    vim.cmd("TmuxNavigateLeft")
    nvim.move_cursor_up()
    nvim_tree_api.node.open.edit()
end, { noremap = true, desc = "Open prev file" })

vim.keymap.set({ "n" }, "H", "^", { noremap = true, desc = "First non-blank" })
vim.keymap.set({ "n" }, "L", "g_", { noremap = true, desc = "Last non-blank" })

-- Perusing code faster with K and J
vim.keymap.set({ "n", "v" }, "K", "5k", { noremap = true, desc = "Up faster" })
vim.keymap.set({ "n", "v" }, "J", "5j", { noremap = true, desc = "Down faster" })

vim.keymap.set({ "v" }, "<", "<gv", { noremap = true, desc = "Remap to save selected" })
vim.keymap.set({ "v" }, ">", ">gv", { noremap = true, desc = "Remap to save selected" })

vim.keymap.set('n', '<leader>fh', '<cmd>Telescope help_tags<cr>', { noremap = true, silent = true })

vim.keymap.set({ "v" }, "<leader>f", refactoring.format_markdown_150, { noremap = true });

-- Remap K and J
vim.keymap.set({ "n", "v" }, "<leader>k", "K", { noremap = true, desc = "Keyword" })
vim.keymap.set({ "n", "v" }, "<leader>j", "J", { noremap = true, desc = "Join lines" })

-- format buf
vim.keymap.set("n", "<leader>f", vim.lsp.buf.format, { noremap = true, silent = true })

-- Save file
vim.keymap.set("n", "<leader>w", "<cmd>w<cr>", { noremap = true, desc = "Save window" })
vim.api.nvim_create_user_command("W", function(opts)
    vim.cmd("w " .. opts.args)
end, { nargs = "*" })
vim.api.nvim_create_user_command("Msg", function(opts)
    vim.cmd("messages " .. opts.args)
end, { nargs = "*" })

-- Quike exit
vim.keymap.set("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quike quite" })

vim.keymap.set("n", "<leader>L", "<cmd>Lazy<cr>", { desc = ":Lazy" })
vim.keymap.set("n", "<leader>vd", nvim.clear_hightlights, { desc = "Remove visual" })

-- lsp shortcut
vim.keymap.set("n", "<leader>ci", "<cmd>LspInfo<cr>", { desc = ":Lazy" })
vim.keymap.set("n", "<leader>cl", "<cmd>LspLog<cr>", { desc = ":Lazy" })
vim.keymap.set("n", "<leader>cr", "<cmd>LspRestart<cr>", { desc = ":Lazy" })

-- llm shortcut
vim.keymap.set("v", "<leader>ls", function()
   ai.ask_english()
end, { noremap = true, desc = ":Lazy" })
vim.keymap.set("v", "<leader>lc", function()
    ai.ask_coder()
end, { noremap = true, desc = ":Lazy" })
vim.keymap.set("n", "<leader>la", function()
   ai.ask()
end, { noremap = true, desc = ":Lazy" })
vim.keymap.set("v", "<leader>la", function()
    ai.ask_v()
end, { noremap = true, desc = ":Lazy" })

-- Lazygit
vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<cr>", { noremap = true, desc = "Open lazygit" })

-- Gen.nvim
vim.keymap.set({ "n", "v" }, "<leader>]", ":Gen<CR>")

-- bsi motions
vim.keymap.set({ "n" }, "<leader>h", dx.highlight_cursor_word, { noremap = true, desc = "Search word in current buffer" })
vim.keymap.set({ "v" }, "<leader>h", dx.highlight_visual, { noremap = true, desc = "Search word in current buffer" })

-- Webify
vim.keymap.set("n", "<leader>o", function()
    webify.open_file_in_browser()
end, { desc = "Open in web browser" })
vim.keymap.set("n", "<leader>O", function()
    webify.open_line_in_browser()
end, { desc = "Open in web browser, including current line" })

-- Spectrume
vim.keymap.set("n", "<leader>S", '<cmd>lua require("spectre").toggle()<CR>', {
    desc = "Toggle Spectre",
})
vim.keymap.set("n", "<leader>sw", '<cmd>lua require("spectre").open_visual({select_word=true})<CR>', {
    desc = "Search current word",
})
vim.keymap.set("v", "<leader>sw", '<esc><cmd>lua require("spectre").open_visual()<CR>', {
    desc = "Search current word",
})
vim.keymap.set("n", "<leader>sp", '<cmd>lua require("spectre").open_file_search({select_word=true})<CR>', {
    desc = "Search on current file",
})

vim.keymap.set("n", "<leader>sw", function()
    local word = nvim.get_cursor_word()
    dx.search_google(word)
end, { desc = "Search word under cur" })

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
    local lines = nvim.get_visual_selection()
    local encodedlines = url_encode(lines)
    dx.search_google(encodedlines)
end, { desc = "Search selected block" })

vim.keymap.set("n", "<D-s>", ":w<CR>", { noremap = true, silent = true })
-- Map Cmd+S to save in insert mode
vim.keymap.set("i", "<D-s>", "<Esc>:w<CR>", { noremap = true, silent = true })

-- Create a custom command to reload the init.lua file
vim.cmd([[
      command! ReloadConfig lua require('user_config').reload_config()
    ]])

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
