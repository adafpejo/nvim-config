local M = {}

local layouts = {
  ["1"] = {
    name = "nvim-tree | buffer",
    cmd = function()
      vim.cmd("NvimTreeOpen")
      vim.cmd("wincmd l")
      if vim.bo.buftype == "" and vim.fn.bufname() == "" then
        vim.cmd("enew")
      end
    end,
  },
  ["2"] = {
    name = "nvim-tree | buffer | git",
    cmd = function()
      vim.cmd("NvimTreeOpen")
      vim.cmd("wincmd l")
      vim.cmd("vsplit")
      vim.cmd("wincmd h")
      vim.cmd("split")
      vim.cmd("wincmd j")
      vim.cmd("terminal git log --oneline --graph --all -20")
      vim.cmd("wincmd k")
      vim.cmd("terminal git branch -a")
      vim.cmd("wincmd =")
    end,
  },
  ["3"] = {
    name = "git index | git diff",
    cmd = function()
      vim.cmd("tabnew")
      vim.cmd("terminal git status -s -b")
      vim.cmd("wincmd l")
      vim.cmd("terminal git diff --stat")
      vim.cmd("wincmd h")
      vim.cmd("wincmd =")
    end,
  },
}

M.current = "1"

function M.apply(id)
  if not layouts[id] then
    vim.notify("bsi/ui: unknown layout " .. id, vim.log.levels.ERROR)
    return
  end

  -- Close all non-NvimTree windows safely (keep at least one window)
  local wins = vim.api.nvim_list_wins()
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype ~= "NvimTree" then
      if #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(win, false)
      end
    end
  end

  layouts[id].cmd()
  M.current = id
  vim.notify("bsi/ui: " .. layouts[id].name, vim.log.levels.INFO)
end

-- Quick switchers
function M.cycle()
  local next = (tonumber(M.current) % 3) + 1
  M.apply(tostring(next))
end

-- Keymaps (add to bsi/remap.lua or call manually)
function M.setup_keymaps()
  vim.keymap.set("n", "<leader>u1", function() M.apply("1") end, { desc = "UI layout 1: nvim-tree | buffer" })
  vim.keymap.set("n", "<leader>u2", function() M.apply("2") end, { desc = "UI layout 2: nvim-tree + git branches/commits" })
  vim.keymap.set("n", "<leader>u3", function() M.apply("3") end, { desc = "UI layout 3: git index | diff" })
  vim.keymap.set("n", "<leader>uu", function() M.cycle() end,    { desc = "Cycle UI layouts" })
end

return M
