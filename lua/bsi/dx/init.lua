local nvim = require('bsi.utils.nvim')
local M = {}

function M.open_url(url)
    -- Execute the command to open the default web browser with the search URL
    local open_command
    if vim.fn.has("macunix") == 1 then
        open_command = "open '" .. url .. "'"
    elseif vim.fn.has("unix") == 1 then
        open_command = "xdg-open '" .. url .. "'"
    elseif vim.fn.has("win32") == 1 then
        open_command = "start '" .. url .. "'"
    else
        print("Unsupported OS")
        return
    end
    os.execute(open_command)
end

function M.search_google(text)
    -- URL encode the selected text for safe inclusion in a URL
    local encoded_text = text:gsub(" ", "%%20")

    -- Define the search URL (using Google search)
    local search_url = "https://www.google.com/search?q=" .. encoded_text

    M.open_url(search_url)
end

function M.highlight_visual()
    vim.schedule(function()
        nvim.highlight(nvim.get_visual_selection())
    end)
end

function M.highlight_cursor_word()
    vim.schedule(function()
        nvim.highlight(nvim.get_cursor_word())
    end)
end

return M
