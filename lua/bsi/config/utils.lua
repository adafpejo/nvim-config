function SearchGoogle(text)
    -- URL encode the selected text for safe inclusion in a URL
    local encoded_text = text:gsub(" ", "%%20")

    -- Define the search URL (using Google search)
    local search_url = "https://www.google.com/search?q=" .. encoded_text

    -- Execute the command to open the default web browser with the search URL
    local open_command
    if vim.fn.has('macunix') == 1 then
        open_command = "open '" .. search_url .. "'"
    elseif vim.fn.has('unix') == 1 then
        open_command = "xdg-open '" .. search_url .. "'"
    elseif vim.fn.has('win32') == 1 then
        open_command = "start '" .. search_url .. "'"
    else
        print("Unsupported OS")
        return
    end
    os.execute(open_command)
end
