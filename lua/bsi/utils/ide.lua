local nvim  = require("bsi.utils.nvim")
local async = require("bsi.utils.async")
local git   = require("bsi.git")
local dx    = require("bsi.dx")

local M     = {}

--- Info popup
--- @param str string
function M.info_popup(str)
    vim.notify_popup(str, {
        timeout = 100
    })
end

function M.open_git_repo()
    local remote_url = git.get_remote_origin()
    assert(#remote_url > 0, "Failed to get remote origin")

    local remote_url_https = git.convert_remote_to_https(remote_url)
    dx.open_url(remote_url_https)
end

--- Opens the current commit in the Git repository web interface
function M.open_git_commit()
    local commit_hash = git.get_current_commit_hash()
    assert(commit_hash and #commit_hash > 0, "Failed to get current commit hash")

    local remote_url = git.get_remote_origin()
    assert(remote_url and #remote_url > 0, "Failed to get remote origin")

    local remote_url_https = git.convert_remote_to_https(remote_url)
    local commit_url = string.format("%s/-/commit/%s", remote_url_https, commit_hash)

    dx.open_url(commit_url)
end

--- Opens the current file at the current line in the Git repository web interface
function M.open_git_commit_line()
    local commit_hash = git.get_current_commit_hash()
    assert(commit_hash and #commit_hash > 0, "Failed to get current commit hash")

    local file_path = nvim.get_file_path()
    local line_number = nvim.get_cursor_line_number()

    local repo_root = git.get_repo_root()
    assert(repo_root and #repo_root > 0, "Failed to get repo root")

    local relative_file_path = file_path:gsub('^' .. repo_root .. '/', '')

    local remote_url = git.get_remote_origin()
    assert(remote_url and #remote_url > 0, "Failed to get remote origin")

    local remote_url_https = git.convert_remote_to_https(remote_url)

    local line_url = string.format("%s/-/blob/%s/%s#L%d", remote_url_https, commit_hash, relative_file_path, line_number)

    dx.open_url(line_url)
end

--- Opens the Git repository pipelines page
function M.open_git_pipelines()
    local remote_url = assert(git.get_remote_origin())
    local remote_url_https = git.convert_remote_to_https(remote_url)
    local pipelines_url = string.format("%s/-/pipelines", remote_url_https)
    dx.open_url(pipelines_url)
end

function M.open_gitlab_mr()
    local current_branch = assert(git.get_current_branch())
    local remote_url = assert(git.get_remote_origin())
    local remote_url_https = git.convert_remote_to_https(remote_url)

    local mr_url = remote_url_https .. "/-/merge_requests/new?merge_request%5Bsource_branch%5D=" .. current_branch

    dx.open_url(mr_url)
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
