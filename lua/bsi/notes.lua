-- vim.keymap.set({"n", "v"}, "<leader>nt", function()
--   vim.api.nvim_put({ "## " .. os.date("%Y-%m-%d") }, "c", true, true)
-- end, { desc = "Insert timestamp (YYYY-MM-DD)" })

-- vim.keymap.set({"n", "v"}, "<leader>nts", function()
--   vim.api.nvim_put({ "## " .. os.date("%Y-%m-%d %H:%M") }, "c", true, true)
-- end, { desc = "Insert timestamp (YYYY-MM-DD HH:MM)" })

local function expand_time_slots()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local starts = {}
  local ends = {}
  for i, line in ipairs(lines) do
    if line:match("// start: (%d+):(%d+); step: (%d+) min") then
      local h, m, s = line:match("// start: (%d+):(%d+); step: (%d+) min")
      local time = os.time({year=2000, month=1, day=1, hour=tonumber(h), min=tonumber(m), sec=0})
      table.insert(starts, {line=i, time=time, step_min=tonumber(s)})
    elseif line:match("// end: (%d+):(%d+);") then
      local h, m = line:match("// end: (%d+):(%d+);")
      local time = os.time({year=2000, month=1, day=1, hour=tonumber(h), min=tonumber(m), sec=0})
      table.insert(ends, {line=i, time=time})
    end
  end
  if #starts ~= #ends then
    vim.api.nvim_echo({{"Error: Number of start comments does not match number of end comments.", "ErrorMsg"}}, false, {})
    return
  end
  if #starts == 0 then return end
  -- Sort starts and ends by line number
  table.sort(starts, function(a, b) return a.line < b.line end)
  table.sort(ends, function(a, b) return a.line < b.line end)
  local offset = 0
  for i = 1, #starts do
    local start = starts[i]
    local endd = ends[i]
    if endd.line <= start.line then
      vim.api.nvim_echo({{"Error: End comment before start or invalid pairing.", "ErrorMsg"}}, false, {})
      return
    end
    -- Check for conflicts in original lines
    local conflict = false
    for j = start.line + 1, endd.line - 1 do
      if lines[j]:match("^%d%d:%d%d - %s*[^%s]") then
        conflict = true
        break
      end
    end
    if not conflict then
      -- Generate new lines
      local new_lines = {
        "// start: " .. os.date("%H:%M", start.time) .. "; step: " .. start.step_min .. " min"
      }
      local current = start.time
      local step_sec = start.step_min * 60
      while current <= endd.time do
        table.insert(new_lines, os.date("%H:%M", current) .. " - ")
        current = current + step_sec
      end
      table.insert(new_lines, "// end: " .. os.date("%H:%M", endd.time) .. ";")
      -- Apply with adjusted indices
      local adjusted_start = start.line + offset
      local adjusted_end = endd.line + offset
      local start_idx = adjusted_start - 1
      local end_idx = adjusted_end
      vim.api.nvim_buf_set_lines(0, start_idx, end_idx, false, new_lines)
      -- Update offset
      local replaced_count = adjusted_end - adjusted_start + 1
      offset = offset + #new_lines - replaced_count
    end
    -- If conflict, skip this range
  end
end

-- vim.keymap.set("n", "<leader>nte", expand_time_slots, { desc = "Expand time slots from start/end comments" })

local M = {}

M.roots = {
  { dir = vim.fn.expand("~/_git"), notes = vim.fn.expand("~/_git/semnotes") },
  { dir = vim.fn.expand("~/_my"), notes = vim.fn.expand("~/_my/devnotes") },
}

function M.shift_days(date, days)
  return os.date("*t", os.time({
    year = date.year,
    month = date.month,
    day = date.day + (days or 0),
    hour = 12,
  }))
end

function M.monday(date)
  local delta = (date.wday == 1) and -6 or (2 - date.wday)
  return M.shift_days(date, delta)
end

function M.resolve(project_dir)
  if not project_dir or project_dir == "" then
    return nil, nil
  end
  local path = vim.fs.normalize(project_dir)
  for _, root in ipairs(M.roots) do
    local dir = vim.fs.normalize(root.dir)
    if vim.startswith(path .. "/", dir .. "/") then
      return root.notes, root.notes .. "/worklog"
    end
  end
  return nil, nil
end

function M.note_path(worklog_root, kind, offset, now)
  local shift = offset or 0
  if kind == "week" then
    shift = shift * 7
  end
  local date = M.shift_days(now, shift)
  local start = M.monday(date)
  local finish = M.shift_days(start, 6)
  local ym = string.format("%04d-%02d", start.year, start.month)
  local week = string.format("%02d-%02d", start.day, finish.day)
  local filename = (kind == "day") and string.format("%02d.md", date.day) or "week.md"
  local path = string.format("%s/%s/%s/%s", worklog_root, ym, week, filename)
  return path, date, start, finish
end

function M.apply_template(lines, kind, date, week_start, week_end)
  local function dmy(d)
    return string.format("%02d-%02d-%04d", d.day, d.month, d.year)
  end
  local out = {}
  for _, line in ipairs(lines) do
    if kind == "day" then
      line = line:gsub("{{date}}", dmy(date))
    else
      line = line:gsub("{{start date}}", dmy(week_start))
      line = line:gsub("{{end date}}", dmy(week_end))
    end
    table.insert(out, line)
  end
  return out
end

function M.project_dir()
  local cwd = vim.fn.getcwd()
  local out = vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
    return vim.fs.normalize(out[1])
  end
  return vim.fs.normalize(cwd)
end

local function template_lines(notes_repo, kind)
  local name = (kind == "day") and "day.md" or "week.md"
  local path = notes_repo .. "/tmpls/" .. name
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  return vim.fn.readfile(path)
end

function M.open(kind, offset)
  if kind ~= "day" and kind ~= "week" then
    vim.notify("notes: kind must be day or week", vim.log.levels.WARN)
    return
  end
  local repo, worklog = M.resolve(M.project_dir())
  if not worklog then
    vim.notify("notes: not inside _git or _my", vim.log.levels.WARN)
    return
  end
  local path, date, start, finish = M.note_path(worklog, kind, offset or 0, os.date("*t"))
  local bufnr = vim.fn.bufnr(path)
  local already = bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr)
  local new_file = vim.fn.filereadable(path) == 0
  vim.cmd({ cmd = "edit", args = { path } })
  if new_file and not already then
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = vim.api.nvim_get_current_buf(),
      once = true,
      callback = function()
        if vim.fn.isdirectory(dir) == 0 then
          vim.fn.mkdir(dir, "p")
        end
      end,
    })
    local lines = template_lines(repo, kind)
    if lines and #lines > 0 then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, M.apply_template(lines, kind, date, start, finish))
    end
  end
  vim.notify(vim.fn.fnamemodify(path, ":~"), vim.log.levels.INFO)
end

vim.keymap.set("n", "<leader>nd", function() M.open("day", 0) end, { desc = "Note: current day" })
vim.keymap.set("n", "<leader>np", function() M.open("day", -1) end, { desc = "Note: previous day" })
vim.keymap.set("n", "<leader>nw", function() M.open("week", 0) end, { desc = "Note: current week" })
-- vim.keymap.set("n", "<leader>nwp", function() M.open("week", -1) end, { desc = "Note: previous week" })
vim.keymap.set("n", "<leader>nW", function() M.open("week", -1) end, { desc = "Note: previous week" })

return M

