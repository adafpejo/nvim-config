local M = {}
local tree = require("bsi.ui.tree")
local git_ui = require("bsi.ui.git")
local ctx = require("bsi.ui.context")

local layouts = {
    ["1"] = {
        name = "Tree | Buffer",
        apply = function(root)
            ctx.State.close_current()
            local t = tree.new({ root = root })
            t:open()
            ctx.State.track_window(t.winid)
            ctx.State.track_buffer(t.bufnr)
            ctx.State.active_layout = "1"
            vim.wo[t.winid].winbar = ctx.render_title(t:get_root_path())
            vim.cmd("wincmd l")
        end,
    },
    ["2"] = {
        name = "Tree + Git Grid",
        apply = function(root)
            git_ui.apply_grid(root)
        end,
    },
    ["3"] = {
        name = "Git Index | Diff",
        apply = function(root)
            ctx.State.close_current()
            root = root or vim.fn.getcwd()
            ctx.State.active_layout = "3"

            -- First view
            git_ui.create_git_view({ "git", "-C", root, "status", "--short", "--branch" }, "[1] - status")
            -- Second view
            vim.cmd("wincmd v")
            git_ui.create_git_view({ "git", "-C", root, "diff", "--stat" }, "[2] - diff stat")
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
        if ft ~= "Tree" and vim.bo[buf].buftype ~= "terminal" and ft ~= "" then
            keep[buf] = true
        end
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and not keep[buf] then
            local ft = vim.bo[buf].filetype
            local bt = vim.bo[buf].buftype
            if ft == "Tree" or bt == "terminal" or ft == "GitView" then
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
        if buftype == "terminal" or filetype == "Tree" or filetype == "GitView" or filetype == "qf" or filetype == "help" then
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
