local panel = require("bsi.ui.bsi_diff_view_panel")
local tree_mod = require("bsi.ui.tree")

local MARK = "bsi_diff_view_panel"

local function git(cwd, args)
  local cmd = { "git", "-C", cwd }
  for _, arg in ipairs(args) do
    cmd[#cmd + 1] = arg
  end
  local out = vim.system(cmd, { text = true }):wait()
  assert.equals(0, out.code, out.stderr or out.stdout)
end

local function write_file(path, text)
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, text, 0))
  vim.uv.fs_close(fd)
end

describe("bsi.ui.bsi_diff_view_panel", function()
  it("steps between files and wraps", function()
    local nodes = {
      { type = "directory", name = "src" },
      { type = "file", name = "a" },
      { type = "directory", name = "pkg" },
      { type = "file", name = "b" },
    }
    assert.equals(2, panel.step(nodes, 1, "next", 1))
    assert.equals(4, panel.step(nodes, 2, "next", 1))
    assert.equals(2, panel.step(nodes, 4, "next", 1))
    assert.equals(4, panel.step(nodes, 2, "prev", 1))
    assert.equals(2, panel.step(nodes, 3, "prev", 1))
    assert.is_nil(panel.step({ { type = "directory" } }, 1, "next", 1))
  end)

  describe("panel windows", function()
    local tmp
    local tree

    before_each(function()
      tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      git(tmp, { "init" })
      git(tmp, { "config", "user.email", "t@example.com" })
      git(tmp, { "config", "user.name", "t" })
      write_file(tmp .. "/note.txt", "old\n")
      git(tmp, { "add", "note.txt" })
      git(tmp, { "-c", "commit.gpgsign=false", "commit", "-m", "init" })
      write_file(tmp .. "/note.txt", "new\n")
    end)

    after_each(function()
      if tree then
        panel.close(tree)
        if tree.winid and vim.api.nvim_win_is_valid(tree.winid) then
          pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = tree.winid })
          pcall(vim.api.nvim_win_close, tree.winid, true)
        end
        if tree.bufnr and vim.api.nvim_buf_is_valid(tree.bufnr) then
          pcall(vim.api.nvim_buf_delete, tree.bufnr, { force = true })
        end
        tree = nil
      end
      if tmp then
        vim.fn.delete(tmp, "rf")
        tmp = nil
      end
      local wins = vim.api.nvim_tabpage_list_wins(0)
      for i, win in ipairs(wins) do
        if i < #wins and vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
          pcall(vim.api.nvim_win_close, win, true)
        end
      end
    end)

    local function sides()
      local head, work
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_is_valid(win) and win ~= tree.winid then
          local buf = vim.api.nvim_win_get_buf(win)
          local name = vim.api.nvim_buf_get_name(buf)
          if name:find(MARK, 1, true) and vim.wo[win].diff then
            local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
            local bar = vim.wo[win].winbar or ""
            if bar:find("HEAD", 1, true) then
              head = line
            elseif bar:find("WORK", 1, true) then
              work = line
            end
          end
        end
      end
      return head, work
    end

    it("shows HEAD and worktree in the same tab and keeps the tree focused", function()
      tree = tree_mod.new({ git_view = true, root = tmp })
      tree:open()
      panel.show(tree, tree.root_path .. "/note.txt")
      local ok = vim.wait(4000, function()
        local head, work = sides()
        return head == "old" and work == "new" and vim.api.nvim_get_current_win() == tree.winid
      end)
      local head, work = sides()
      assert.is_true(ok)
      assert.equals("old", head)
      assert.equals("new", work)
      assert.equals(tree.winid, vim.api.nvim_get_current_win())
      assert.equals(tree.bufnr, vim.api.nvim_win_get_buf(tree.winid))
      assert.equals(1, #vim.api.nvim_list_tabpages())
      assert.equals(3, #vim.api.nvim_tabpage_list_wins(0))
      local borrowed = false
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          local name = vim.api.nvim_buf_get_name(buf)
          if name:find("diffview://", 1, true) then
            borrowed = true
          end
        end
      end
      assert.is_false(borrowed)
    end)

    it("switches files in the same windows and close leaves the tab and the tree", function()
      write_file(tmp .. "/other.txt", "aaa\n")
      git(tmp, { "add", "other.txt" })
      git(tmp, { "-c", "commit.gpgsign=false", "commit", "-m", "other" })
      write_file(tmp .. "/other.txt", "bbb\n")
      tree = tree_mod.new({ git_view = true, root = tmp })
      tree:open()
      panel.show(tree, tree.root_path .. "/note.txt")
      assert.is_true(vim.wait(4000, function()
        local head, work = sides()
        return head == "old" and work == "new" and vim.api.nvim_get_current_win() == tree.winid
      end))
      local left = tree._bsi_a
      local right = tree._bsi_b
      panel.show(tree, tree.root_path .. "/other.txt")
      local switched = vim.wait(4000, function()
        local head, work = sides()
        return head == "aaa" and work == "bbb" and vim.api.nvim_get_current_win() == tree.winid
      end)
      assert.is_true(switched)
      assert.equals(left, tree._bsi_a)
      assert.equals(right, tree._bsi_b)
      assert.equals(3, #vim.api.nvim_tabpage_list_wins(0))
      local tab = vim.api.nvim_get_current_tabpage()
      panel.close(tree)
      assert.equals(tab, vim.api.nvim_get_current_tabpage())
      assert.equals(1, #vim.api.nvim_list_tabpages())
      assert.is_true(vim.api.nvim_win_is_valid(tree.winid))
      local extra = 0
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= tree.winid and vim.api.nvim_win_is_valid(win) then
          extra = extra + 1
        end
      end
      assert.equals(0, extra)
    end)

    it("q closes the panel and opens the filesystem tree and the previous buffer", function()
      write_file(tmp .. "/keep.txt", "keep\n")
      git(tmp, { "add", "keep.txt" })
      git(tmp, { "-c", "commit.gpgsign=false", "commit", "-m", "keep" })
      vim.cmd("edit " .. vim.fn.fnameescape(tmp .. "/keep.txt"))
      tree = tree_mod.new({ git_view = true, root = tmp })
      tree:open()
      panel.show(tree, tree.root_path .. "/note.txt")
      assert.is_true(vim.wait(4000, function()
        local head, work = sides()
        return head == "old" and work == "new" and vim.api.nvim_get_current_win() == tree.winid
      end))
      assert.is_not_nil(tree._bsi_b)
      vim.api.nvim_set_current_win(tree._bsi_b)
      vim.cmd("normal q")
      assert.is_false(tree.git_view)
      assert.is_true(vim.api.nvim_win_is_valid(tree.winid))
      assert.equals(1, #vim.api.nvim_list_tabpages())
      local saw_keep = false
      local saw_panel = false
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          local name = vim.api.nvim_buf_get_name(buf)
          if name:find(MARK, 1, true) then
            saw_panel = true
          end
          if win ~= tree.winid and name:find("keep.txt", 1, true) then
            local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
            if line == "keep" then
              saw_keep = true
            end
          end
        end
      end
      assert.is_false(saw_panel)
      assert.is_true(saw_keep)
      local names = {}
      for _, child in ipairs(tree.state.root.children or {}) do
        names[child.name] = true
      end
      assert.is_true(names["keep.txt"])
      assert.is_true(names["note.txt"])
      assert.equals(tree.bufnr, vim.api.nvim_win_get_buf(tree.winid))
    end)
  end)
end)
