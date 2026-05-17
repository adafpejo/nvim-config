local M = {}
local tree = require("bsi.tree")

local layouts = {
  ["1"] = {
    name = "Tree | Buffer",
    apply = function()
      vim.cmd("only")
      tree.new():open()
      vim.cmd("wincmd l")
    end,
  },
  ["2"] = {
    name = "Tree | Branches | Commits",
    apply = function()
      vim.cmd("only")
      vim.api.nvim_set_hl(0, "BSITreeTitle", { fg = "#3EFFDC", bold = true })

      -- Left: Tree (creates sidebar)
      local t = tree.new()
      t:open()
      vim.wo[t.winid].winbar = "%#BSITreeTitle# [1] - tree"

      -- Branches below Tree
      vim.cmd("belowright split")
      vim.cmd("terminal git branch --all")
      vim.wo.winbar = "%#BSITreeTitle# [2] - branches"

      -- Commits below Branches
      vim.cmd("belowright split")
      vim.cmd("terminal git log --oneline --graph --all -20")
      vim.wo.winbar = "%#BSITreeTitle# [3] - commits"

      -- Return to main buffer on the right
      vim.cmd("wincmd l")
    end,
  },
  ["3"] = {
    name = "Git Index | Diff",
    apply = function()
      vim.cmd("only")
      vim.cmd("terminal git status --short --branch")
      vim.cmd("wincmd v")
      vim.cmd("terminal git diff --stat")
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
      if ft == "bsitree" or bt == "terminal" then
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

  cleanup()
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
  vim.keymap.set("n", "<leader>uu", function() M.cycle() end,  { desc = "Cycle UI layouts" })

  -- Quick window navigation
  vim.keymap.set("n", "1", "1<C-w>w", { desc = "Jump to Window 1 (Tree)" })
  vim.keymap.set("n", "2", "2<C-w>w", { desc = "Jump to Window 2 (Branches)" })
  vim.keymap.set("n", "3", "3<C-w>w", { desc = "Jump to Window 3 (Commits)" })
  vim.keymap.set("n", "4", "4<C-w>w", { desc = "Jump to Window 4 (Main Buffer)" })
end

return M
