local async = require("bsi.utils.async")

local M = {}

--- highlight text sentence inside current buffer
--- @param word string
function M.highlight(word)
    -- Clear previous highlights if any
    vim.cmd("match none")
    -- Search for the word and highlight it
    vim.cmd("match Search /" .. vim.fn.escape(word, "/") .. "/")
end

function M.move_cursor_down()
    local current_pos = vim.api.nvim_win_get_cursor(0)
    local new_line = current_pos[1] + 1
    vim.api.nvim_win_set_cursor(0, { new_line, current_pos[2] })
end

function M.move_cursor_up()
    local current_pos = vim.api.nvim_win_get_cursor(0)
    local new_line = math.max(current_pos[1] - 1, 1)
    vim.api.nvim_win_set_cursor(0, { new_line, current_pos[2] })
end

--- Get word under cursor
--- @return string
function M.get_cursor_word()
    return vim.fn.expand("<cword>")
end

function M.clear_hightlights()
    vim.cmd("match none")
end

function M.concat_to_single_str(lines)
    return table.concat(lines, '\n')
end

function M.save_to_clipboard(lines)
    vim.fn.setreg('+', lines)
end

function M.stop_lsp_byname(name)
    -- Check if yamlls is attached to the buffer
    local clients = vim.lsp.get_active_clients({ bufnr = 0 })
    for _, client in ipairs(clients) do
        if client.name == name then
            vim.lsp.stop_client(client.id)
            return
        end
    end
end

function M.assert_empty_string(var, error_msg)
    if not var or var == "" then
        error(error_msg)
    end
end

--- Trim whitespaces
--- @param s string
--- @return string
function M.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

--- System async
--- @param cmd string
--- @return string concat result
function M.system_async(cmd)
    local co = async.co.running()
    async.assert_co(co, 'system_async')

    local result = { output = "", error = "", exit_code = nil }

    -- Start the job asynchronously
    vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            if data then
                if data[#data] == "" then table.remove(data, #data) end
                result.output = table.concat(data, "\n")
            end
        end,
        on_stderr = function(_, data)
            if data then
                if data[#data] == "" then table.remove(data, #data) end
                result.error = table.concat(data, "\n")
            end
        end,
        on_exit = function(_, code)
            result.exit_code = code
            async.resume(co, result)
        end,
    })

    return async.co.yield()
end

-- Function to execute a system command with a timeout
function M.system_with_timeout(cmd, timeout)
    local co = async.co.running()
    async.assert_co(co, 'system_with_timeout')

    local result = { output = "", error = "", exit_code = nil }
    local timer = vim.loop.new_timer()

    -- Start the job asynchronously
    local job_id = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            if data then
                if data[#data] == "" then table.remove(data, #data) end
                result.output = table.concat(data, "\n")
            end
        end,
        on_stderr = function(_, data)
            if data then
                if data[#data] == "" then table.remove(data, #data) end
                result.error = table.concat(data, "\n")
            end
        end,
        on_exit = function(_, code)
            result.exit_code = code
            timer:stop()
            timer:close()
            async.resume(co, result)
        end,
    })

    -- Set up the timer to enforce the timeout
    timer:start(timeout, 0, function()
        if result.exit_code == nil then
            vim.schedule(function()
                -- Job is still running; stop it
                vim.fn.jobstop(job_id)
                result.error = "Command timed out"
                result.exit_code = -1
                -- already in wraper
                async.co.resume(co, result)
            end)
        end
    end)

    return async.co.yield()
end

--- Return current visual selection of V or v
--- multiline concatend by `\n`
--- @return string
function M.get_visual_selection()
    local _, srow, scol = unpack(vim.fn.getpos('v'))
    local _, erow, ecol = unpack(vim.fn.getpos('.'))

    -- visual line mode
    if vim.fn.mode() == 'V' then
        if srow > erow then
            return M.concat_to_single_str(vim.api.nvim_buf_get_lines(0, erow - 1, srow, true))
        else
            return M.concat_to_single_str(vim.api.nvim_buf_get_lines(0, srow - 1, erow, true))
        end
    end

    -- regular visual mode
    if vim.fn.mode() == 'v' then
        if srow < erow or (srow == erow and scol <= ecol) then
            return M.concat_to_single_str(vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {}))
        else
            return M.concat_to_single_str(vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {}))
        end
    end

    -- visual block mode
    if vim.fn.mode() == '\22' then
        local lines = {}
        if srow > erow then
            srow, erow = erow, srow
        end
        if scol > ecol then
            scol, ecol = ecol, scol
        end
        for i = srow, erow do
            table.insert(
                lines,
                vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1]
            )
        end

        return M.concat_to_single_str(lines)
    end
end

function M.emulate_A()
    vim.api.nvim_command("normal! A")
end

function M.send_message(text)
    vim.api.nvim_echo({ { text, "None" } }, true, {})
end

return M
