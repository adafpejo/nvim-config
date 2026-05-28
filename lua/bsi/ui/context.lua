local M = {}

M.State = {
    active_layout = nil,
    windows = {},
    buffers = {},
}

function M.State.reset()
    M.State.active_layout = nil
    M.State.windows = {}
    M.State.buffers = {}
end

function M.State.track_window(win)
    if win and vim.api.nvim_win_is_valid(win) then
        table.insert(M.State.windows, win)
    end
end

function M.State.track_buffer(buf)
    if buf and vim.api.nvim_buf_is_valid(buf) then
        table.insert(M.State.buffers, buf)
    end
end

function M.State.close_current()
    -- Close windows first
    for _, win in ipairs(M.State.windows) do
        if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
    -- Delete buffers
    for _, buf in ipairs(M.State.buffers) do
        if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
    M.State.reset()
end

function M.render_title(title)
  vim.api.nvim_set_hl(0, "BSITreeTitle", { fg = "#3EFFDC", bold = true })
  return "%#BSITreeTitle# " .. title
end

return M
