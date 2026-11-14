local tree_mod = require("bsi.ui.tree")

local uv = vim.uv or vim.loop

local function mkdir(path)
  vim.fn.mkdir(path, "p")
end

local function write_file(path, contents)
  mkdir(vim.fn.fnamemodify(path, ":h"))
  local fd = assert(uv.fs_open(path, "w", 420))
  uv.fs_write(fd, contents, 0)
  uv.fs_close(fd)
end

local function read_file(path)
  local fd = uv.fs_open(path, "r", 420)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  local data = uv.fs_read(fd, stat and stat.size or 0, 0)
  uv.fs_close(fd)
  return data
end

local function child_by_name(node, name)
  for _, c in ipairs(node.children or {}) do
    if c.name == name or c.name:match("^" .. name .. "/") then
      return c
    end
  end
end

describe("bsi.ui.tree yank and paste", function()
  local tmp
  local input = vim.ui.input

  after_each(function()
    tree_mod.file_clip = nil
    tree_mod.cat_buf = nil
    vim.ui.input = input
    if tmp then
      vim.fn.delete(tmp, "rf")
      tmp = nil
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if vim.bo[buf].filetype == "Tree" or name:match("BSI Cat$") then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end
    local wins = vim.api.nvim_tabpage_list_wins(0)
    for i, win in ipairs(wins) do
      if i < #wins and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = vim.api.nvim_get_current_win() })
  end)

  it("puts the yanked name on the paste registers immediately", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/page.tsx", "x")
    local t = tree_mod.new({ root = tmp })
    t.visible_nodes = {
      { name = "page.tsx", path = t.root_path .. "/src/app/page.tsx", type = "file" },
    }
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    t:_yank(false)
    assert.equals("page.tsx", vim.fn.getreg('"'))
    assert.equals("page.tsx", vim.fn.getreg("+"))
    t:_yank(true)
    assert.equals("src/app/page.tsx", vim.fn.getreg('"'))
    assert.equals("src/app/page.tsx", vim.fn.getreg("+"))
  end)

  it("pastes a copied file into another directory", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/dest")
    write_file(tmp .. "/note.txt", "hello")
    local t = tree_mod.new({ root = tmp })
    local note = child_by_name(t.state.root, "note.txt")
    local dest = child_by_name(t.state.root, "dest")
    assert.is_not_nil(note)
    assert.is_not_nil(dest)

    t:stage_clipboard(note, "copy")
    assert.equals("copy", tree_mod.file_clip.action)
    t:paste_clipboard(dest)

    assert.equals("hello", read_file(t.root_path .. "/dest/note.txt"))
    assert.equals("hello", read_file(t.root_path .. "/note.txt"))
    assert.is_nil(tree_mod.file_clip)
  end)

  it("pastes onto a file into that file's parent", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/dest")
    write_file(tmp .. "/note.txt", "hello")
    write_file(tmp .. "/dest/other.txt", "o")
    local t = tree_mod.new({ root = tmp })
    local note = child_by_name(t.state.root, "note.txt")
    t:stage_clipboard(note, "copy")
    t:paste_clipboard({
      type = "file",
      path = t.root_path .. "/dest/other.txt",
      name = "other.txt",
    })
    assert.equals("hello", read_file(t.root_path .. "/dest/note.txt"))
  end)

  it("copies a directory tree", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/src/sub")
    mkdir(tmp .. "/dest")
    write_file(tmp .. "/src/keep.txt", "K")
    write_file(tmp .. "/src/sub/b.txt", "B")
    local t = tree_mod.new({ root = tmp })
    local src = child_by_name(t.state.root, "src")
    local dest = child_by_name(t.state.root, "dest")
    t:stage_clipboard(src, "copy")
    t:paste_clipboard(dest)
    assert.equals("B", read_file(t.root_path .. "/dest/src/sub/b.txt"))
    assert.equals("B", read_file(t.root_path .. "/src/sub/b.txt"))
  end)

  it("cuts a file and prunes the empty parent", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/nested")
    write_file(tmp .. "/nested/a.txt", "A")
    write_file(tmp .. "/keep.txt", "K")
    local t = tree_mod.new({ root = tmp })
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, t.root_path .. "/nested/a.txt")

    t:stage_clipboard({
      type = "file",
      path = t.root_path .. "/nested/a.txt",
      name = "a.txt",
    }, "cut")
    t:paste_clipboard(t.state.root)

    assert.equals("A", read_file(t.root_path .. "/a.txt"))
    assert.is_nil(uv.fs_stat(t.root_path .. "/nested/a.txt"))
    assert.is_nil(uv.fs_stat(t.root_path .. "/nested"))
    assert.equals("K", read_file(t.root_path .. "/keep.txt"))
    assert.is_nil(tree_mod.file_clip)
    assert.equals(
      vim.fs.normalize(t.root_path .. "/a.txt"),
      vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
    )
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("clears the stage when the same key is pressed again", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/note.txt", "x")
    local t = tree_mod.new({ root = tmp })
    local note = child_by_name(t.state.root, "note.txt")
    t:stage_clipboard(note, "copy")
    t:stage_clipboard(note, "cut")
    assert.equals("cut", tree_mod.file_clip.action)
    t:stage_clipboard(note, "cut")
    assert.is_nil(tree_mod.file_clip)
  end)

  it("does not stage the root", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    local t = tree_mod.new({ root = tmp })
    t:stage_clipboard(t.state.root, "copy")
    assert.is_nil(tree_mod.file_clip)
  end)

  it("does nothing when nothing is staged", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/note.txt", "x")
    local t = tree_mod.new({ root = tmp })
    tree_mod.file_clip = nil
    t:paste_clipboard(t.state.root)
    assert.equals("x", read_file(t.root_path .. "/note.txt"))
    assert.is_nil(uv.fs_stat(t.root_path .. "/note-copy.txt"))
  end)

  it("asks for another path instead of overwriting", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/dest")
    write_file(tmp .. "/note.txt", "new")
    write_file(tmp .. "/dest/note.txt", "keep")
    local t = tree_mod.new({ root = tmp })
    local note = child_by_name(t.state.root, "note.txt")
    local dest = child_by_name(t.state.root, "dest")
    local prompted
    vim.ui.input = function(opts, cb)
      prompted = opts.default
      cb(t.root_path .. "/dest/note-renamed.txt")
    end

    t:stage_clipboard(note, "copy")
    t:paste_clipboard(dest)

    assert.is_truthy(prompted)
    assert.equals("note-copy.txt", vim.fn.fnamemodify(prompted, ":t"))
    assert.equals("keep", read_file(t.root_path .. "/dest/note.txt"))
    assert.equals("new", read_file(t.root_path .. "/dest/note-renamed.txt"))
    assert.equals("new", read_file(t.root_path .. "/note.txt"))
    assert.is_nil(tree_mod.file_clip)
  end)

  it("does not paste a directory into itself", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/src/sub")
    write_file(tmp .. "/src/keep.txt", "K")
    write_file(tmp .. "/src/sub/b.txt", "B")
    local t = tree_mod.new({ root = tmp })
    local src = child_by_name(t.state.root, "src")
    t:stage_clipboard(src, "copy")
    t:paste_clipboard(src)
    assert.is_nil(uv.fs_stat(t.root_path .. "/src/src"))
    assert.equals("B", read_file(t.root_path .. "/src/sub/b.txt"))
    assert.is_not_nil(tree_mod.file_clip)
  end)

  it("highlights a staged name", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/note.txt", "x")
    local t = tree_mod.new({ root = tmp })
    local note = child_by_name(t.state.root, "note.txt")
    local nodes = { note }

    tree_mod.file_clip = { action = "copy", paths = { note.path } }
    local copied = t.renderer:build(nodes)
    local saw_copy = false
    for _, hl in ipairs(copied.highlights) do
      if hl.hl == "BSITreeCopied" then
        saw_copy = true
      end
    end
    assert.is_true(saw_copy)

    tree_mod.file_clip = { action = "cut", paths = { note.path } }
    local cut = t.renderer:build(nodes)
    local saw_cut = false
    for _, hl in ipairs(cut.highlights) do
      if hl.hl == "BSITreeCut" then
        saw_cut = true
      end
    end
    assert.is_true(saw_cut)
  end)

  it("copies the visual line range and pastes each file", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/dest")
    write_file(tmp .. "/a.txt", "A")
    write_file(tmp .. "/b.txt", "B")
    local t = tree_mod.new({ root = tmp })
    local a = child_by_name(t.state.root, "a.txt")
    local b = child_by_name(t.state.root, "b.txt")
    local dest = child_by_name(t.state.root, "dest")
    t.visible_nodes = { a, b }
    t:copy_lines(1, 2)

    assert.equals("copy", tree_mod.file_clip.action)
    assert.same({ a.path, b.path }, tree_mod.file_clip.paths)
    t:paste_clipboard(dest)
    assert.equals("A", read_file(t.root_path .. "/dest/a.txt"))
    assert.equals("B", read_file(t.root_path .. "/dest/b.txt"))
    assert.equals("A", read_file(t.root_path .. "/a.txt"))
    assert.is_nil(tree_mod.file_clip)
  end)

  it("does not stage a file that sits inside a staged directory", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/src")
    write_file(tmp .. "/src/keep.txt", "K")
    local t = tree_mod.new({ root = tmp })
    local src = child_by_name(t.state.root, "src")
    t:stage_clipboard({
      src,
      { type = "file", path = t.root_path .. "/src/keep.txt", name = "keep.txt" },
    }, "copy")
    local staged = vim.fs.normalize(src.path):gsub("/$", "")
    assert.same({ staged }, tree_mod.file_clip.paths)
  end)

  it("cats one file and the files directly inside a directory", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/dir/sub")
    write_file(tmp .. "/dir/b.txt", "B")
    write_file(tmp .. "/dir/a.txt", "A")
    write_file(tmp .. "/dir/sub/hidden.txt", "NESTED")
    write_file(tmp .. "/dir/bin.dat", "a\0b")
    local t = tree_mod.new({ root = tmp })
    local note = { type = "file", path = t.root_path .. "/dir/a.txt", name = "a.txt" }
    assert.equals("A", t:cat_text(note))

    local dir = child_by_name(t.state.root, "dir")
    local text = t:cat_text(dir)
    assert.equals(table.concat({
      "==> a.txt <==",
      "A",
      "",
      "==> b.txt <==",
      "B",
      "",
      "==> bin.dat <==",
      "[binary 3 bytes]",
    }, "\n"), text)
    assert.is_nil(text:find("NESTED", 1, true))
  end)

  it("visual y copies the selected rows", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/a.txt", "A")
    write_file(tmp .. "/b.txt", "B")
    local t = tree_mod.new({ root = tmp })
    t:open()
    vim.api.nvim_set_current_win(t.winid)
    vim.api.nvim_win_set_cursor(t.winid, { 1, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("Vjy", true, false, true), "xt", false)
    assert.is_not_nil(tree_mod.file_clip)
    assert.equals("copy", tree_mod.file_clip.action)
    assert.equals(2, #tree_mod.file_clip.paths)
  end)

  it("copies file contents onto the paste registers", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/dir/sub")
    write_file(tmp .. "/note.txt", "hello")
    write_file(tmp .. "/dir/a.txt", "A")
    write_file(tmp .. "/dir/sub/hidden.txt", "NESTED")
    local t = tree_mod.new({ root = tmp })
    local wins = #vim.api.nvim_list_wins()

    local note = { type = "file", path = t.root_path .. "/note.txt", name = "note.txt" }
    assert.equals("hello", t:copy_contents(note))
    assert.equals("hello", vim.fn.getreg('"'))
    assert.equals("hello", vim.fn.getreg("+"))
    assert.equals(wins, #vim.api.nvim_list_wins())

    local dir = child_by_name(t.state.root, "dir")
    local listed = t:copy_contents(dir)
    assert.equals(listed, vim.fn.getreg('"'))
    assert.equals(listed, vim.fn.getreg("+"))
    assert.is_not_nil(listed:find("A", 1, true))
    assert.is_nil(listed:find("NESTED", 1, true))
    assert.equals(wins, #vim.api.nvim_list_wins())
  end)

  it("y stages the file itself", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/note.txt", "hello")
    local t = tree_mod.new({ root = tmp })
    local note = child_by_name(t.state.root, "note.txt")
    t.visible_nodes = { note }
    t.winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    t:_stage_cursor("copy")
    assert.equals("copy", tree_mod.file_clip.action)
    assert.same({ note.path }, tree_mod.file_clip.paths)
    assert.equals("hello", read_file(note.path))
  end)
end)
