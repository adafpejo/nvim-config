local nvim = require("bsi.utils.nvim")
local async = require("bsi.utils.async")

local M = {}

--- Info popup
--- @param str string
function M.info_popup(str)
    vim.notify_popup(str, {
        timeout = 100
    })
end

--- Open inline input one string
--- Runtime: coroutine
---
function M.open_inline_input()
    local co = async.co.running()
    async.assert_co(co, 'open_inline_input');

    -- Get the current cursor position and buffer
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local buf = vim.api.nvim_create_buf(false, true)

    -- Calculate window position
    local width = 30
    local win_opts = {
        relative = "win",
        width = width,
        height = 1,
        row = row - 1, -- Adjust to match cursor position
        col = col,
        style = "minimal",
        border = "rounded",
    }

    -- Create the floating window
    local win = vim.api.nvim_open_win(buf, true, win_opts)

    -- Set the initial content of the buffer with the prompt
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })

    -- Enable insert mode
    nvim.emulate_A()

    local function close_input()
        vim.api.nvim_win_close(win, true)              -- Close the floating window
        vim.api.nvim_buf_delete(buf, { force = true }) -- Delete the buffer
    end

    -- Function to handle input
    local function get_user_input()
        vim.cmd("stopinsert")
        local input = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        close_input()
        return input
    end

    vim.keymap.set("i", "<CR>", function()
        vim.schedule(function()
            async.co.resume(co, get_user_input())
        end)
    end, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set({ "n", "i" }, "<ESC>", close_input, { buffer = buf, noremap = true, silent = true })

    return async.co.yield()
end

return M
