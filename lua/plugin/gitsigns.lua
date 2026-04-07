local nvim    = require("bsi.utils.nvim")
local git     = require("bsi.git")

local gitsigns = require('gitsigns')
gitsigns.setup()

-- toogle blame by default
gitsigns.toggle_current_line_blame()

vim.keymap.set('n', '<leader>hs', gitsigns.stage_hunk)
vim.keymap.set('n', '<leader>hr', gitsigns.reset_hunk)
vim.keymap.set('v', '<leader>hs', function() gitsigns.stage_hunk { vim.fn.line('.'), vim.fn.line('v') } end)
vim.keymap.set('v', '<leader>hr', function() gitsigns.reset_hunk { vim.fn.line('.'), vim.fn.line('v') } end)
vim.keymap.set('n', '<leader>hS', gitsigns.stage_buffer)
vim.keymap.set('n', '<leader>gs', function()
    local file_path = nvim.get_file_path()
    local line_number = nvim.get_cursor_line_number()

    local repo_root = git.get_repo_root()
    assert(repo_root and #repo_root > 0, "Failed to get repo root")

    -- Ensure file is tracked in git
    assert(git.is_file_tracked(file_path), "File is not tracked in git")

    local commit_hash = git.get_blame_commit_hash(file_path, line_number)
    assert(commit_hash and #commit_hash > 0, "Failed to get blame commit hash")

    gitsigns.show_commit(commit_hash, 'tabnew')
end)
vim.keymap.set('n', '<leader>gl', function()
    local file_path = nvim.get_file_path()
    local line_number = nvim.get_cursor_line_number()

    local repo_root = git.get_repo_root()
    assert(repo_root and #repo_root > 0, "Failed to get repo root")

    -- Ensure file is tracked in git
    assert(git.is_file_tracked(file_path), "File is not tracked in git")

    local commits = git.get_current_line_commits(file_path, line_number)
    if not commits or #commits == 0 then
        vim.cmd("echo 'No commits found for this line'")
        return
    end

    -- Show commits in a new buffer with keymaps
    vim.cmd("enew")
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
    vim.api.nvim_buf_set_lines(0, 0, -1, false, commits)

    -- Keymap to select commit on Enter
    vim.keymap.set('n', '<CR>', function()
        local line = vim.api.nvim_get_current_line()
        local commit_hash = line:match("^(%S+)")
        if commit_hash then
            gitsigns.show_commit(commit_hash, 'tabnew')
        end
    end, { buffer = true })

    vim.cmd("wincmd L | vertical resize 50") -- Open as vertical split on the right, resize to 50 columns
end)
vim.keymap.set('n', '<leader>gd', function()
    -- local commit_hash = git.get_current_commit_hash()
    -- assert(commit_hash and #commit_hash > 0, "Failed to get blame commit hash")
    local base_commit = git.get_base_commit()

    vim.cmd("DiffviewOpen " .. base_commit .. "..HEAD")
end)
vim.keymap.set('n', '<leader>hu', gitsigns.undo_stage_hunk)
vim.keymap.set('n', '<leader>hR', gitsigns.reset_buffer)
vim.keymap.set('n', '<leader>th', gitsigns.preview_hunk)
vim.keymap.set('n', '<leader>hb', function() gitsigns.blame_line { full = true } end)
vim.keymap.set('n', '<leader>tb', gitsigns.toggle_current_line_blame)
vim.keymap.set('n', '<leader>hd', gitsigns.diffthis)
vim.keymap.set('n', '<leader>hD', function() gitsigns.diffthis('~') end)
vim.keymap.set('n', '<leader>td', gitsigns.toggle_deleted)

