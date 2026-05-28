local M = {}
local tree = require("bsi.ui.tree")
local Cmd = require("bsi.cmd")
local ctx = require("bsi.ui.context")

local function set_git_view_mappings(bufnr)
    for i = 1, 4 do
        vim.keymap.set("n", tostring(i), i .. "<C-w>w", { buffer = bufnr, silent = true, desc = "Jump to window " .. i })
    end
end

function M.create_git_view(cmd, title)
    local State = ctx.State
    local render_title = ctx.render_title

    vim.cmd("belowright split")
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)

    State.track_window(win)
    State.track_buffer(buf)

    pcall(vim.api.nvim_buf_set_name, buf, "GitView: " .. title)
    vim.bo[buf].filetype = "GitView"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].modifiable = false

    set_git_view_mappings(buf)
    vim.wo.winbar = render_title(title)

    Cmd.new(cmd, {
        cwd = vim.fn.getcwd(),
        on_success = function(c)
            local output = c:job().stdout
            local lines = vim.split(output, "\n")
            if vim.api.nvim_buf_is_valid(buf) then
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.bo[buf].modifiable = false
            end
        end,
        on_error = function(c)
            local output = c:job().stderr
            local lines = vim.split(output, "\n")
            if vim.api.nvim_buf_is_valid(buf) then
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.bo[buf].modifiable = false
            end
        end
    })

    return buf
end

function M.apply_grid(root)
    local State = ctx.State
    local render_title = ctx.render_title

    State.close_current()

    -- Left: Tree (creates sidebar)
    local t = tree.new({ git_only = true, root = root })
    t:open()
    State.track_window(t.winid)
    State.track_buffer(t.bufnr)
    State.active_layout = "2"

    local tree_root = t.root_path -- Use the raw root path
    vim.wo[t.winid].winbar = render_title("[1] r: " .. t:get_root_path())

    -- Branches below Tree
    M.create_git_view({ "git", "-C", tree_root, "branch", "--all" }, "[2] - branches")

    -- Commits below Branches
    M.create_git_view({ "git", "-C", tree_root, "log", "--oneline", "--graph", "--all", "-20" }, "[3] - commits")

    -- GitView below Commits
    M.create_git_view({ "git", "-C", tree_root, "status", "--short", "--branch" }, "[4] - git status")

    -- Set sidebar proportions
    local wins = State.windows
    if #wins >= 4 then
        local total_h = 0
        for _, w in ipairs(wins) do
            total_h = total_h + vim.api.nvim_win_get_height(w)
        end

        vim.api.nvim_win_set_height(wins[1], math.floor(total_h * 0.4))
        vim.api.nvim_win_set_height(wins[2], math.floor(total_h * 0.2))
        vim.api.nvim_win_set_height(wins[3], math.floor(total_h * 0.2))
        vim.api.nvim_win_set_height(wins[4], math.floor(total_h * 0.2))
    end

    -- Return to main buffer on the right
    vim.cmd("wincmd l")
end

return M
