local git_tree = require("bsi.ui.git_tree")
local tree_mod = require("bsi.ui.tree")

local function mkdir(path)
  vim.fn.mkdir(path, "p")
end

local function touch(path)
  mkdir(vim.fn.fnamemodify(path, ":h"))
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  vim.uv.fs_close(fd)
end

local function child_by_name(node, name)
  for _, child in ipairs(node.children or {}) do
    if child.name == name then
      return child
    end
  end
end

describe("bsi.ui.git_tree", function()
  local tmp

  before_each(function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
  end)

  after_each(function()
    if tmp then
      vim.fn.delete(tmp, "rf")
      tmp = nil
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "Tree" then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    local wins = vim.api.nvim_tabpage_list_wins(0)
    for i, win in ipairs(wins) do
      if i < #wins and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    local win = vim.api.nvim_get_current_win()
    pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
  end)

  it("lists only changed files and collapses a single directory chain", function()
    local file = tmp .. "/src/pkg/main.go"
    local other = tmp .. "/README.md"
    touch(file)
    touch(other)
    touch(tmp .. "/skip.txt")
    local root = git_tree.build(tmp, {
      [file] = " M",
      [other] = "??",
      [tmp .. "/skip.txt"] = "!!",
      [tmp .. "/gone.txt"] = "D ",
      ["/elsewhere/nope.txt"] = "M ",
    })
    local src = child_by_name(root, "src/pkg")
    assert.is_not_nil(src)
    assert.equals("directory", src.type)
    assert.is_true(src.expanded)
    local main = child_by_name(src, "main.go")
    assert.equals("file", main.type)
    assert.equals("M", main.git_letter)
    local readme = child_by_name(root, "README.md")
    assert.equals("A", readme.git_letter)
    local gone = child_by_name(root, "gone.txt")
    assert.equals("D", gone.git_letter)
    assert.is_nil(child_by_name(root, "skip.txt"))
    assert.is_nil(child_by_name(root, "nope.txt"))
    assert.equals("DMA", root.git_status_summary)
  end)

  it("keeps a directory collapsed across apply_collapsed", function()
    local file = tmp .. "/src/pkg/main.go"
    touch(file)
    local root = git_tree.build(tmp, { [file] = " M" })
    local src = child_by_name(root, "src/pkg")
    git_tree.apply_collapsed(root, { [src.path] = true })
    assert.is_false(src.expanded)
  end)

  it("does not scan the filesystem when created as a git view", function()
    touch(tmp .. "/a.txt")
    touch(tmp .. "/b.txt")
    local t = tree_mod.new({ git_view = true, root = tmp })
    assert.is_true(t.git_view)
    assert.equals(0, #(t.state.root.children or {}))
  end)

end)
