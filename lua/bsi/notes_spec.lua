local notes = require("bsi.notes")

local function on(year, month, day)
  return os.date("*t", os.time({ year = year, month = month, day = day, hour = 12 }))
end

describe("bsi.notes", function()
  local root

  before_each(function()
    root = "/Users/bogdanovsi/_git/semnotes/worklog"
  end)

  it("puts a date in the Monday week under the Monday month", function()
    local path = notes.note_path(root, "day", 0, on(2026, 11, 9))
    assert.are.equal(root .. "/2026-11/09-15/09.md", path)

    path = notes.note_path(root, "day", 0, on(2026, 11, 15))
    assert.are.equal(root .. "/2026-11/09-15/15.md", path)

    path = notes.note_path(root, "week", 0, on(2026, 11, 12))
    assert.are.equal(root .. "/2026-11/09-15/week.md", path)
  end)

  it("keeps month-crossing days in the Monday month folder", function()
    local path = notes.note_path(root, "day", 0, on(2026, 12, 1))
    assert.are.equal(root .. "/2026-11/30-06/01.md", path)

    path = notes.note_path(root, "day", 0, on(2026, 11, 30))
    assert.are.equal(root .. "/2026-11/30-06/30.md", path)

    path = notes.note_path(root, "day", 0, on(2027, 1, 3))
    assert.are.equal(root .. "/2026-12/28-03/03.md", path)

    path = notes.note_path(root, "day", -1, on(2027, 1, 1))
    assert.are.equal(root .. "/2026-12/28-03/31.md", path)
  end)

  it("steps a week back by seven days", function()
    local path = notes.note_path(root, "week", -1, on(2026, 12, 9))
    assert.are.equal(root .. "/2026-11/30-06/week.md", path)

    path = notes.note_path(root, "week", -1, on(2026, 11, 16))
    assert.are.equal(root .. "/2026-11/09-15/week.md", path)

    path = notes.note_path(root, "day", -1, on(2026, 11, 16))
    assert.are.equal(root .. "/2026-11/09-15/15.md", path)
  end)

  it("resolves semnotes for _git and devnotes for _my", function()
    local repo, worklog = notes.resolve("/Users/bogdanovsi/_git/bat-lbt")
    assert.are.equal("/Users/bogdanovsi/_git/semnotes", repo)
    assert.are.equal("/Users/bogdanovsi/_git/semnotes/worklog", worklog)

    repo, worklog = notes.resolve("/Users/bogdanovsi/_my/devnotes")
    assert.are.equal("/Users/bogdanovsi/_my/devnotes", repo)
    assert.are.equal("/Users/bogdanovsi/_my/devnotes/worklog", worklog)

    repo, worklog = notes.resolve("/Users/bogdanovsi/_git")
    assert.are.equal("/Users/bogdanovsi/_git/semnotes/worklog", worklog)

    repo, worklog = notes.resolve("/Users/bogdanovsi/_gitfoo/app")
    assert.is_nil(repo)
    assert.is_nil(worklog)

    repo, worklog = notes.resolve("/Users/bogdanovsi/.config/nvim")
    assert.is_nil(worklog)
  end)

  it("fills day and week template placeholders", function()
    local date = on(2026, 11, 9)
    local start = notes.monday(date)
    local finish = notes.shift_days(start, 6)
    local day_lines = notes.apply_template({ "# {{date}} | Day" }, "day", date, start, finish)
    assert.are.same({ "# 09-11-2026 | Day" }, day_lines)

    local week_lines = notes.apply_template(
      { "# Week {{start date}} – {{end date}}" },
      "week",
      date,
      start,
      finish
    )
    assert.are.same({ "# Week 09-11-2026 – 15-11-2026" }, week_lines)
  end)

  it("opens a new note and creates parent dirs on write", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/notes/tmpls", "p")
    vim.fn.writefile({ "# {{date}} | Day" }, tmp .. "/notes/tmpls/day.md")

    local orig_roots = notes.roots
    local orig_dir = notes.project_dir
    notes.roots = { { dir = tmp .. "/repo", notes = tmp .. "/notes" } }
    notes.project_dir = function()
      return tmp .. "/repo/app"
    end

    local ok, err = pcall(function()
      notes.open("day", 0)
      local expected = notes.note_path(tmp .. "/notes/worklog", "day", 0, os.date("*t"))
      assert.are.equal(vim.fs.normalize(expected), vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
      local first = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
      assert.is_nil(first:find("{{date}}", 1, true))
      assert.is_not_nil(first:find("| Day", 1, true))
      assert.are.equal(0, vim.fn.isdirectory(vim.fn.fnamemodify(expected, ":h")))
      vim.cmd("write")
      assert.are.equal(1, vim.fn.filereadable(expected))
    end)

    pcall(vim.cmd, "bdelete!")
    vim.fn.delete(tmp, "rf")
    notes.roots = orig_roots
    notes.project_dir = orig_dir
    assert.is_true(ok, err)
  end)

  it("refuses a project outside both roots", function()
    local orig_dir = notes.project_dir
    local seen
    local orig_notify = vim.notify
    notes.project_dir = function()
      return "/tmp/not-a-notes-root"
    end
    vim.notify = function(msg)
      seen = msg
    end
    local ok, err = pcall(notes.open, "day", 0)
    notes.project_dir = orig_dir
    vim.notify = orig_notify
    assert.is_true(ok, err)
    assert.is_not_nil(seen:find("not inside", 1, true))
  end)
end)
