local nvim = require('bsi.utils.nvim')
--- External deps:
--- brew install graphviz
--- plantuml.jar

-- vim.api.nvim_create_user_command('PlantUML', function()
--   M.open_term_float({
--         'java -jar' .. ' ' .. vim.fn.expand("~/.local/share/plantuml.jar") .. '-pipe < ' .. vim.fn.expand('%:p') .. ' | kitty +kitten icat'
--     }, {
--     title = 'PlantUML',
--     border = 'rounded',
--   })
-- end, {})

local render_plantuml_cmd = function()
    local file = vim.fn.shellescape(vim.api.nvim_buf_get_name(0))
    return ('java -jar ~/.local/share/plantuml.jar -tpng -pipe < %s | kitty +kitten icat --stdin yes'):format(file)
end

vim.api.nvim_create_user_command('PlantUML', function()
    local cmd = render_plantuml_cmd()
    vim.notify_popup(cmd)
    nvim.save_to_clipboard(cmd)

    -- vim.cmd('vnew') -- Create vertical split with scratch buffer (or adjust)
    -- local bufnr = vim.api.nvim_get_current_buf()
    -- vim.api.nvim_buf_set_name(bufnr, 'PlantUML Preview')

    -- vim.cmd('startinsert')

    -- vim.fn.jobstart(cmd, {
    --     stdio = { nil, nil, nil }, -- stdin=nil, stdout=nil (use callbacks), stderr=nil
    --     on_stdout = function(job_id, data, event)
    --         -- data is a table of lines (each entry is a line or chunk)
    --         -- Note: data includes trailing empty strings if the output ends with a newline
    --         if data then
    --             -- Concatenate all lines into a single string for output
    --             local output = table.concat(data, '\n')
    --             if output ~= "" then
    --                 -- Use nvim_echo to display the captured data
    --                 -- Note: This will echo the output to Neovim's message/command line area.
    --                 -- If the data is graphics escape codes, they may not render graphically here
    --                 -- (unlike nvim_out_write, which sends to stdout for Kitty to draw).
    --                 -- nvim_echo expects a list of chunks (each with text and optional highlight).
    --                 -- For simplicity, treat the entire output as one chunk with no special highlighting.
    --                 vim.api.nvim_echo({ { output } }, false, {})
    --             end
    --         end
    --         vim.print(data)
    --     end,
    --     on_exit = function(job_id, code, event)
    --         -- Handle job exit
    --         print('Job finished with code:', code)
    --         -- Optional: Exit insert mode or refresh
    --         vim.cmd('stopinsert')
    --     end,
    -- })
end, {})

return {}
