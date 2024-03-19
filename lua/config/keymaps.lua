-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- vim.keymap.set("n", "<C-/>", "<cmd>ToggleTermToggleAll<CR>")

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
end, { desc = "Toggle Copilot" })
