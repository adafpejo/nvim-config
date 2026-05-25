local M = {}
local tree = require("bsi.tree")

local Cmd = require("bsi.cmd")

local State = {
    active_layout = nil,
    windows = {},
    buffers = {},
}

function State.reset()
    State.active_layout = nil
    State.windows = {}
    State.buffers = {}
end

function State.track_window(win)
    if win and vim.api.nvim_win_is_valid(win) then
        table.insert(State.windows, win)
    end
end

function State.track_buffer(buf)
    if buf and vim.api.nvim_buf_is_valid(buf) then
        table.insert(State.buffers, buf)
    end
end

function State.close_current()
    -- Close windows first
    for _, win in ipairs(State.windows) do
        if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
    -- Delete buffers
    for _, buf in ipairs(State.buffers) do
        if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
    State.reset()
end

vim.api.nvim_set_hl(0, "BSITreeTitle", { fg = "#3EFFDC", bold = true })

local render_title = function(title)
  return "%#BSITreeTitle# " .. title
end

local function set_git_view_mappings(bufnr)
    for i = 1, 4 do
        vim.keymap.set("n", tostring(i), i .. "<C-w>w", { buffer = bufnr, silent = true, desc = "Jump to window " .. i })
    end
end

local function create_git_view(cmd, title)
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

local layouts = {
    ["1"] = {
        name = "Tree | Buffer",
        apply = function(root)
            State.close_current()
            local t = tree.new({ root = root })
            t:open()
            State.track_window(t.winid)
            State.track_buffer(t.bufnr)
            State.active_layout = "1"
            vim.wo[t.winid].winbar = render_title(t:get_root_path())
            vim.cmd("wincmd l")
        end,
    },
    ["2"] = {
        name = "Tree + Git Grid",
        apply = function(root)
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
            create_git_view({ "git", "-C", tree_root, "branch", "--all" }, "[2] - branches")

            -- Commits below Branches
            create_git_view({ "git", "-C", tree_root, "log", "--oneline", "--graph", "--all", "-20" }, "[3] - commits")

            -- GitView below Commits
            create_git_view({ "git", "-C", tree_root, "status", "--short", "--branch" }, "[4] - git status")

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
        end,
    },
    ["3"] = {
        name = "Git Index | Diff",
        apply = function(root)
            State.close_current()
            root = root or vim.fn.getcwd()
            State.active_layout = "3"
            
            -- First view
            create_git_view({ "git", "-C", root, "status", "--short", "--branch" }, "[1] - status")
            -- Second view
            vim.cmd("wincmd v")
            create_git_view({ "git", "-C", root, "diff", "--stat" }, "[2] - diff stat")
            vim.cmd("wincmd =")
        end,
    },
}

M.current = "1"

local function cleanup()
    local keep = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.bo[buf].filetype
        -- Keep current non-tree non-terminal buffers
        if ft ~= "bsitree" and vim.bo[buf].buftype ~= "terminal" and ft ~= "" then
            keep[buf] = true
        end
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and not keep[buf] then
            local ft = vim.bo[buf].filetype
            local bt = vim.bo[buf].buftype
            if ft == "bsitree" or bt == "terminal" or ft == "GitView" then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
        end
    end
end

function M.apply(id)
    if not layouts[id] then
        vim.notify("UI: unknown layout " .. id, vim.log.levels.ERROR)
        return
    end

    layouts[id].apply()
    M.current = id
    vim.notify("Layout → " .. layouts[id].name, vim.log.levels.INFO)
end

function M.cycle()
    local next_id = tostring(tonumber(M.current) % #vim.tbl_keys(layouts) + 1)
    M.apply(next_id)
end

function M.setup_keymaps()
    local function apply_and_focus(id)
        M.apply(id)
        -- Ensure focus is on the main buffer (usually rightmost)
        vim.cmd("wincmd l")
    end

    vim.keymap.set("n", "<leader>u1", function() apply_and_focus("1") end, { desc = "UI: Tree | Buffer" })
    vim.keymap.set("n", "<leader>u2", function() apply_and_focus("2") end, { desc = "UI: Tree + Git Grid" })
    vim.keymap.set("n", "<leader>u3", function() apply_and_focus("3") end, { desc = "UI: Git Index | Diff" })
    vim.keymap.set("n", "<leader>uu", function() M.cycle() end, { desc = "Cycle UI layouts" })

    -- Quick window navigation (only in non-regular buffers)
    local function jump_or_type(n)
        local buftype = vim.bo.buftype
        local filetype = vim.bo.filetype
        if buftype == "terminal" or filetype == "bsitree" or filetype == "qf" or filetype == "help" then
            vim.cmd(n .. "wincmd w")
        else
            vim.api.nvim_feedkeys(n, "n", true)
        end
    end

    vim.keymap.set("n", "1", function() jump_or_type("1") end, { desc = "Jump to Window 1" })
    vim.keymap.set("n", "2", function() jump_or_type("2") end, { desc = "Jump to Window 2" })
    vim.keymap.set("n", "3", function() jump_or_type("3") end, { desc = "Jump to Window 3" })
    vim.keymap.set("n", "4", function() jump_or_type("4") end, { desc = "Jump to Window 4" })
end

return M
