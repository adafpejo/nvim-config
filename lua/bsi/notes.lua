vim.keymap.set({"n", "v"}, "<leader>nt", function()
  vim.api.nvim_put({ "## " .. os.date("%Y-%m-%d") }, "c", true, true)
end, { desc = "Insert timestamp (YYYY-MM-DD)" })

vim.keymap.set({"n", "v"}, "<leader>nts", function()
  vim.api.nvim_put({ "## " .. os.date("%Y-%m-%d %H:%M") }, "c", true, true)
end, { desc = "Insert timestamp (YYYY-MM-DD HH:MM)" })

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

vim.keymap.set("n", "<leader>nte", expand_time_slots, { desc = "Expand time slots from start/end comments" })

