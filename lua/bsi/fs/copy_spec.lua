local copy = require("bsi.fs.copy")

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

describe("bsi.fs.copy", function()
  local tmp

  after_each(function()
    if tmp then
      vim.fn.delete(tmp, "rf")
      tmp = nil
    end
  end)

  it("copies file bytes", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/note.txt", "a\0b\n")
    local result = copy(tmp .. "/note.txt", tmp .. "/out.txt")
    assert.is_true(result.ok)
    assert.equals("file", result.kind)
    assert.equals("a\0b\n", read_file(tmp .. "/out.txt"))
    assert.equals("a\0b\n", read_file(tmp .. "/note.txt"))
  end)

  it("copies a directory tree", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/src/sub")
    write_file(tmp .. "/src/a.txt", "A")
    write_file(tmp .. "/src/sub/b.txt", "B")
    local result = copy(tmp .. "/src", tmp .. "/dst")
    assert.is_true(result.ok)
    assert.equals("dir", result.kind)
    assert.equals("A", read_file(tmp .. "/dst/a.txt"))
    assert.equals("B", read_file(tmp .. "/dst/sub/b.txt"))
    assert.equals("A", read_file(tmp .. "/src/a.txt"))
  end)

  it("copies an empty directory", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/empty")
    local result = copy(tmp .. "/empty", tmp .. "/empty2")
    assert.is_true(result.ok)
    assert.equals("dir", result.kind)
    local stat = uv.fs_stat(tmp .. "/empty2")
    assert.is_not_nil(stat)
    assert.equals("directory", stat.type)
  end)

  it("copies a symlink as a symlink", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/target.txt", "body")
    assert.is_true(uv.fs_symlink("target.txt", tmp .. "/link.txt"))
    local result = copy(tmp .. "/link.txt", tmp .. "/link2.txt")
    assert.is_true(result.ok)
    assert.equals("link", result.kind)
    local stat = uv.fs_lstat(tmp .. "/link2.txt")
    assert.is_not_nil(stat)
    assert.equals("link", stat.type)
    assert.equals("target.txt", uv.fs_readlink(tmp .. "/link2.txt"))
  end)

  it("does not overwrite an existing destination", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/src.txt", "new")
    write_file(tmp .. "/dst.txt", "keep")
    local result = copy(tmp .. "/src.txt", tmp .. "/dst.txt")
    assert.is_false(result.ok)
    assert.equals("exists", result.kind)
    assert.equals("keep", read_file(tmp .. "/dst.txt"))
    assert.equals("new", read_file(tmp .. "/src.txt"))
  end)

  it("refuses to copy a directory into itself", function()
    tmp = vim.fn.tempname()
    mkdir(tmp .. "/dir/sub")
    write_file(tmp .. "/dir/a.txt", "A")
    local result = copy(tmp .. "/dir", tmp .. "/dir/sub/dir")
    assert.is_false(result.ok)
    assert.equals("invalid", result.kind)
    assert.is_nil(uv.fs_stat(tmp .. "/dir/sub/dir"))
    assert.equals("A", read_file(tmp .. "/dir/a.txt"))
  end)

  it("reports a missing source and does not create the destination", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    local result = copy(tmp .. "/missing.txt", tmp .. "/out.txt")
    assert.is_false(result.ok)
    assert.equals("missing", result.kind)
    assert.is_nil(uv.fs_stat(tmp .. "/out.txt"))
  end)

  it("does not remove an existing path when the destination parent is a file", function()
    tmp = vim.fn.tempname()
    mkdir(tmp)
    write_file(tmp .. "/not-a-dir", "keep")
    write_file(tmp .. "/src.txt", "new")
    local result = copy(tmp .. "/src.txt", tmp .. "/not-a-dir/out.txt")
    assert.is_false(result.ok)
    assert.equals("keep", read_file(tmp .. "/not-a-dir"))
  end)
end)
