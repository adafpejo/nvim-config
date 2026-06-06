local nvim   = require("bsi.utils.nvim")
local async  = require("bsi.utils.async")
local git    = require("bsi.git")
local system = require("bsi.system")
local webify = require("bsi.webify")

local M     = {}

-- ============================================================================
-- bsi.ide
--
-- High-level "IDE" actions for git + web forge integration.
--
-- This module combines:
--   - Git repository logic (current branch, commit, blame, remote, etc. from bsi.git)
--   - Web URL construction for files (delegated to bsi.webify for current file + line)
--   - Consistent forge-aware URL building (via bsi.git)
--
-- URL construction logic for remotes lives in `git/remote.lua`, not here.
-- ============================================================================

--- Info popup
--- @param str string
function M.info_popup(str)
    vim.notify_popup(str, {
        timeout = 100
    })
end

function M.open_git_repo()
    local remote_url_https = git.get_remote_origin_https()
    assert(remote_url_https and #remote_url_https > 0, "Failed to get remote origin")

    system.open_url(remote_url_https)
end

--- Opens the current commit in the Git repository web interface.
function M.open_git_commit()
    local commit_url = git.build_current_commit_url()
    assert(commit_url, "Failed to build URL for current commit")
    system.open_url(commit_url)
end

--- Opens the file at the blamed commit + current line in the Git web UI.
--- This shows the file content as of the commit that introduced the line.
--- Uses promoted builder from git module.
function M.open_git_commit_blame()
    local file_path = nvim.get_file_path()
    local line_number = nvim.get_cursor_line_number()

    local repo_root = git.get_repo_root()
    assert(repo_root and #repo_root > 0, "Failed to get repo root")

    -- Ensure file is tracked in git
    assert(git.is_file_tracked(file_path), "File is not tracked in git")

    local commit_hash = git.get_blame_commit_hash(file_path, line_number)
    assert(commit_hash and #commit_hash > 0, "Failed to get blame commit hash")

    local relative_file_path = file_path:gsub('^' .. repo_root .. '/', '')

    local remote = git.get_remote_origin()
    assert(remote and #remote > 0, "Failed to get remote origin")

    local line_url = git.build_blob_url(remote, commit_hash, relative_file_path, line_number)
    system.open_url(line_url)
end

--- Opens the Git repository pipelines / actions page.
--- Delegates to git.remote for the correct path per forge.
function M.open_git_pipelines()
    local remote = git.get_remote_origin()
    assert(remote and #remote > 0, "Failed to get remote origin")

    local pipelines_url = git.build_pipelines_url(remote)
    system.open_url(pipelines_url)
end

function M.open_gitlab_mr()
    -- This action is GitLab-oriented (the merge request creation URL shape
    -- and query param are specific to GitLab's UI).
    local current_branch = assert(git.get_current_branch())
    local remote_url_https = git.get_remote_origin_https()
    assert(remote_url_https and #remote_url_https > 0, "Failed to get remote origin")

    local mr_url = remote_url_https .. "/-/merge_requests/new?merge_request%5Bsource_branch%5D=" .. current_branch

    system.open_url(mr_url)
end

-- ============================================================================
-- File browser / webify integration
-- Combined here so that `bsi.ide` is the single high-level module for
-- git-forge web actions (repo, commits, files, blame, pipelines, MRs, etc.).
-- ============================================================================

--- Open the current file in the repository's web interface (on current branch).
M.open_file_in_browser = webify.open_file_in_browser

--- Open the current file + current line in the web interface.
M.open_line_in_browser = webify.open_line_in_browser

--- Copy URL to current file to clipboard.
M.yank_file_url = webify.yank_file_url

--- Copy URL to current file + line to clipboard.
M.yank_line_url = webify.yank_line_url

--- Return (do not open) the URL for the current file.
M.get_file_url = webify.get_file_url

--- Return (do not open) the URL for the current file + line.
M.get_line_url = webify.get_line_url

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

--- Highlight the current visual selection in the buffer (uses Search match highlight)
function M.highlight_visual()
    vim.schedule(function()
        nvim.highlight(nvim.get_visual_selection())
    end)
end

--- Highlight the word under the cursor in the buffer (uses Search match highlight)
function M.highlight_cursor_word()
    vim.schedule(function()
        nvim.highlight(nvim.get_cursor_word())
    end)
end

return M
