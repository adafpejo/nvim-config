local M = {}

local MARK = "bsi_diff_view_panel"

function M.step(nodes, row, direction, count)
  local files = {}
  for i, node in ipairs(nodes or {}) do
    if node.type == "file" then
      files[#files + 1] = i
    end
  end
  if #files == 0 then
    return nil
  end
  count = count or 1
  if count < 1 then
    count = 1
  end
  local at
  for i, line in ipairs(files) do
    if line == row then
      at = i
      break
    end
  end
  local idx
  if at then
    local delta = direction == "prev" and -count or count
    idx = ((at - 1 + delta) % #files) + 1
  elseif direction == "prev" then
    idx = 1
    for i = #files, 1, -1 do
      if files[i] < row then
        idx = i
        break
      end
    end
    if count > 1 then
      idx = ((idx - 1 - (count - 1)) % #files) + 1
    end
  else
    idx = #files
    for i, line in ipairs(files) do
      if line > row then
        idx = i
        break
      end
    end
    if count > 1 then
      idx = ((idx - 1 + (count - 1)) % #files) + 1
    end
  end
  return files[idx]
end

function M.pair_line(hunks, line, from_head)
  line = line or 1
  if line < 1 then
    line = 1
  end
  local delta = 0
  for _, h in ipairs(hunks or {}) do
    local sa, ca, sb, cb = h[1] or 0, h[2] or 0, h[3] or 0, h[4] or 0
    local src_s, src_c, dst_s, dst_c
    if from_head then
      src_s, src_c, dst_s, dst_c = sa, ca, sb, cb
    else
      src_s, src_c, dst_s, dst_c = sb, cb, sa, ca
    end
    if src_c == 0 then
      if line <= src_s then
        local mapped = line + delta
        if mapped < 1 then
          mapped = 1
        end
        return mapped
      end
      delta = delta + dst_c
    else
      local src_last = src_s + src_c - 1
      if line < src_s then
        local mapped = line + delta
        if mapped < 1 then
          mapped = 1
        end
        return mapped
      end
      if line <= src_last then
        if dst_c == 0 then
          if dst_s < 1 then
            return 1
          end
          return dst_s
        end
        local rel = line - src_s
        local add = math.floor(rel * dst_c / src_c)
        if add >= dst_c then
          add = dst_c - 1
        end
        return dst_s + add
      end
      delta = delta + (dst_c - src_c)
    end
  end
  local mapped = line + delta
  if mapped < 1 then
    mapped = 1
  end
  return mapped
end

function M.change_lines(h)
  local sa = h[1] or 0
  local sb = h[3] or 0
  local head = sa
  local work = sb
  if head < 1 then
    head = 1
  end
  if work < 1 then
    work = 1
  end
  return head, work
end

local function repo_rel(root, abs)
  root = root or ""
  abs = abs or ""
  root = root:gsub("/+$", "")
  root = vim.fn.resolve(root)
  abs = vim.fn.resolve(abs)
  if root ~= "" and abs:sub(1, #root + 1) == root .. "/" then
    return abs:sub(#root + 2)
  end
  return abs
end

local function text_lines(text)
  if not text or text == "" then
    return { "" }
  end
  if text:find("\0", 1, true) then
    return { "Binary file" }
  end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local rows = vim.split(text, "\n", { plain = true })
  if #rows > 1 and rows[#rows] == "" then
    rows[#rows] = nil
  end
  if #rows == 0 then
    return { "" }
  end
  return rows
end

local function read_disk(path)
  local uv = vim.uv or vim.loop
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  local data = uv.fs_read(fd, stat and stat.size or 0, 0) or ""
  uv.fs_close(fd)
  return data
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function unlock(win)
  if not valid_win(win) then
    return
  end
  pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
  pcall(vim.api.nvim_set_option_value, "winfixwidth", false, { win = win })
  pcall(vim.api.nvim_set_option_value, "winfixheight", false, { win = win })
end

function M.remember(tree)
  if not tree or tree._bsi_saved_path and tree._bsi_saved_path ~= "" then
    return
  end
  if not valid_win(tree.winid) then
    return
  end
  local tab = vim.api.nvim_win_get_tabpage(tree.winid)
  local fallback
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if win ~= tree.winid and win ~= tree._bsi_a and win ~= tree._bsi_b and valid_win(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local name = vim.api.nvim_buf_get_name(buf)
      if vim.bo[buf].buftype == "" and not name:find(MARK, 1, true) then
        if name ~= "" then
          tree._bsi_saved_buf = buf
          tree._bsi_saved_path = name
          return
        end
        fallback = buf
      end
    end
  end
  if fallback and not tree._bsi_saved_buf then
    tree._bsi_saved_buf = fallback
  end
end

local function focus_tree(tree)
  if valid_win(tree.winid) then
    pcall(vim.api.nvim_set_current_win, tree.winid)
  end
end

local function fill(buf, text, path)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text_lines(text))
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  local ft = vim.filetype.match({ filename = path }) or ""
  if ft ~= "" then
    vim.bo[buf].filetype = ft
  end
end

local function paint(win, title)
  if valid_win(win) then
    pcall(function()
      vim.wo[win].winbar = title
    end)
  end
end

local function sync_diff(win)
  if not valid_win(win) then
    return
  end
  vim.api.nvim_win_call(win, function()
    if vim.wo.diff then
      pcall(vim.cmd, "diffupdate")
    else
      pcall(vim.cmd, "diffthis")
    end
    vim.wo.scrollbind = false
    vim.wo.cursorbind = false
  end)
end

local function diff_indices(head, work)
  local fn = (vim.text and vim.text.diff) or vim.diff
  local ok, hunks = pcall(fn, head or "", work or "", { result_type = "indices" })
  if ok and type(hunks) == "table" then
    return hunks
  end
  return {}
end

local function topline(win)
  return vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0")
  end)
end

local function align_top(win, line)
  if not valid_win(win) then
    return
  end
  local last = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  if line < 1 then
    line = 1
  end
  if line > last then
    line = last
  end
  pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
  vim.api.nvim_win_call(win, function()
    if vim.fn.line("w0") ~= line then
      pcall(vim.cmd, "normal! zt")
    end
  end)
end

local function release_sync(tree)
  vim.schedule(function()
    if tree then
      tree._bsi_syncing = false
    end
  end)
end

local function align_change(tree, head_line, work_line)
  tree._bsi_syncing = true
  align_top(tree._bsi_a, work_line)
  align_top(tree._bsi_b, head_line)
  release_sync(tree)
end

local function hook_scroll(tree)
  if tree._bsi_scroll_au then
    return
  end
  local group = vim.api.nvim_create_augroup("BsiDiffViewPanel", { clear = true })
  tree._bsi_scroll_au = group
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function()
      if tree._bsi_syncing then
        return
      end
      local cur = vim.api.nvim_get_current_win()
      local other
      local from_head
      if cur == tree._bsi_a then
        other = tree._bsi_b
        from_head = false
      elseif cur == tree._bsi_b then
        other = tree._bsi_a
        from_head = true
      else
        return
      end
      if not valid_win(other) then
        return
      end
      local mapped = M.pair_line(tree._bsi_hunks, topline(cur), from_head)
      tree._bsi_syncing = true
      align_top(other, mapped)
      release_sync(tree)
    end,
  })
end

local function drop_scroll(tree)
  if tree._bsi_scroll_au then
    pcall(vim.api.nvim_del_augroup_by_id, tree._bsi_scroll_au)
    tree._bsi_scroll_au = nil
  end
end

local function drop_win(win)
  if not valid_win(win) then
    return
  end
  unlock(win)
  vim.api.nvim_win_call(win, function()
    pcall(vim.cmd, "diffoff")
  end)
  pcall(vim.api.nvim_win_close, win, true)
end

function M.close(tree)
  if not tree then
    return
  end
  tree._bsi_gen = (tree._bsi_gen or 0) + 1
  tree._bsi_placed = false
  tree._bsi_editor_cleared = false
  drop_scroll(tree)
  drop_win(tree._bsi_a)
  drop_win(tree._bsi_b)
  tree._bsi_a = nil
  tree._bsi_b = nil
  tree._bsi_a_buf = nil
  tree._bsi_b_buf = nil
  tree._bsi_hunks = nil
end

local function pane_width(tree, win)
  if not valid_win(win) then
    return
  end
  local minw = 16
  local tree_w = valid_win(tree.winid) and vim.api.nvim_win_get_width(tree.winid) or 30
  local maxw = math.max(minw, (vim.o.columns or 120) - tree_w - minw)
  return minw, maxw
end

function M.nudge(tree, delta, win)
  if not tree then
    return
  end
  win = win or tree._bsi_a
  if win ~= tree._bsi_a and win ~= tree._bsi_b then
    win = tree._bsi_a
  end
  if not valid_win(win) then
    return
  end
  local other = win == tree._bsi_a and tree._bsi_b or tree._bsi_a
  if valid_win(other) then
    pcall(vim.api.nvim_set_option_value, "winfixwidth", false, { win = other })
  end
  local minw, maxw = pane_width(tree, win)
  local cur = vim.api.nvim_win_get_width(win)
  local w = cur + (delta or 0)
  if w < minw then
    w = minw
  end
  if w > maxw then
    w = maxw
  end
  pcall(vim.api.nvim_set_option_value, "winfixwidth", true, { win = win })
  if cur ~= w then
    vim.api.nvim_win_set_width(win, w)
  end
  if win == tree._bsi_a then
    tree._bsi_pane_width = w
    tree._bsi_pane_width_b = nil
  else
    tree._bsi_pane_width_b = w
    tree._bsi_pane_width = nil
  end
end

local function apply_width(tree)
  if tree._bsi_pane_width and valid_win(tree._bsi_a) then
    pcall(vim.api.nvim_set_option_value, "winfixwidth", true, { win = tree._bsi_a })
    pcall(vim.api.nvim_win_set_width, tree._bsi_a, tree._bsi_pane_width)
  end
  if tree._bsi_pane_width_b and valid_win(tree._bsi_b) then
    pcall(vim.api.nvim_set_option_value, "winfixwidth", true, { win = tree._bsi_b })
    pcall(vim.api.nvim_win_set_width, tree._bsi_b, tree._bsi_pane_width_b)
  end
end

local function jump_one(tree, dir)
  local hunks = tree._bsi_hunks or {}
  if #hunks == 0 or not valid_win(tree._bsi_a) then
    return false
  end
  local cur = vim.api.nvim_win_get_cursor(tree._bsi_a)[1]
  local pick
  if dir < 0 then
    for i = #hunks, 1, -1 do
      local _, work = M.change_lines(hunks[i])
      if work < cur then
        pick = hunks[i]
        break
      end
    end
  else
    for _, h in ipairs(hunks) do
      local _, work = M.change_lines(h)
      if work > cur then
        pick = h
        break
      end
    end
  end
  if not pick then
    return false
  end
  local head_line, work_line = M.change_lines(pick)
  local back = vim.api.nvim_get_current_win()
  align_change(tree, head_line, work_line)
  if valid_win(back) then
    pcall(vim.api.nvim_set_current_win, back)
  end
  return true
end

function M.jump(tree, dir)
  if not tree then
    return
  end
  local times = dir or 1
  local step = 1
  if times < 0 then
    step = -1
    times = -times
  end
  if times < 1 then
    times = 1
  end
  for _ = 1, times do
    if not jump_one(tree, step) then
      return
    end
  end
end

local function arm_keys(tree, buf, win)
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", function()
    M.quit(tree)
  end, vim.tbl_extend("force", opts, { desc = "Close BsiDiffViewPanel" }))
  vim.keymap.set("n", ">", function()
    M.nudge(tree, 8, win)
  end, vim.tbl_extend("force", opts, { desc = "Widen diff pane" }))
  vim.keymap.set("n", "<", function()
    M.nudge(tree, -8, win)
  end, vim.tbl_extend("force", opts, { desc = "Narrow diff pane" }))
  vim.keymap.set("n", "]c", function()
    M.jump(tree, vim.v.count1)
  end, vim.tbl_extend("force", opts, { desc = "Next change" }))
  vim.keymap.set("n", "[c", function()
    M.jump(tree, -vim.v.count1)
  end, vim.tbl_extend("force", opts, { desc = "Previous change" }))
  vim.keymap.set("n", "i", function()
    M.open_in_tree(tree)
  end, vim.tbl_extend("force", opts, { desc = "Open file in tree" }))
end

local function make_side(tree, role)
  vim.api.nvim_set_current_win(tree.winid)
  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  unlock(win)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, MARK .. "://" .. role .. "/" .. buf)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_var(win, MARK, role)
  vim.wo[win].wrap = false
  vim.wo[win].foldmethod = "diff"
  vim.wo[win].scrollbind = false
  vim.wo[win].cursorbind = false
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = win })
  arm_keys(tree, buf, win)
  return win, buf
end

local function side_mark(win)
  if not valid_win(win) then
    return nil
  end
  local ok, val = pcall(vim.api.nvim_win_get_var, win, MARK)
  if ok then
    return val
  end
end

local function side_ok(tree, win, buf, role)
  return valid_win(win)
    and side_mark(win) == role
    and buf
    and vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_win_get_buf(win) == buf
end

local function ensure(tree)
  if side_ok(tree, tree._bsi_a, tree._bsi_a_buf, "a") and side_ok(tree, tree._bsi_b, tree._bsi_b_buf, "b") then
    return true
  end
  M.close(tree)
  if not valid_win(tree.winid) then
    return false
  end
  M.remember(tree)
  tree._bsi_a, tree._bsi_a_buf = make_side(tree, "a")
  tree._bsi_b, tree._bsi_b_buf = make_side(tree, "b")
  hook_scroll(tree)
  return true
end

local function clear_editor(tree)
  if tree._bsi_editor_cleared or not valid_win(tree.winid) then
    return
  end
  local keep = {
    [tree.winid] = true,
    [tree._bsi_a] = true,
    [tree._bsi_b] = true,
  }
  local tab = vim.api.nvim_win_get_tabpage(tree.winid)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if not keep[win] and valid_win(win) then
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative == "" then
        unlock(win)
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
  tree._bsi_editor_cleared = true
end

local function place(tree)
  if tree._bsi_placed or not valid_win(tree.winid) then
    return
  end
  focus_tree(tree)
  pcall(vim.cmd, "wincmd H")
  tree._bsi_placed = true
end

local function unmap_tree(tree)
  tree._git_keys_bound = false
  if not tree.bufnr or not vim.api.nvim_buf_is_valid(tree.bufnr) then
    return
  end
  for _, lhs in ipairs({ "j", "k", "]c", "[c", "i" }) do
    pcall(vim.keymap.del, "n", lhs, { buffer = tree.bufnr })
  end
  vim.keymap.set("n", ">", function()
    tree:nudge_width(3)
  end, { buffer = tree.bufnr, silent = true, desc = "Tree: Widen tree by 3 columns" })
  vim.keymap.set("n", "<", function()
    tree:nudge_width(-3)
  end, { buffer = tree.bufnr, silent = true, desc = "Tree: Narrow tree by 3 columns" })
end

local function show_saved(tree, buf, path)
  if not valid_win(tree.winid) then
    return
  end
  local named = path and path ~= ""
  local plain = buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
  if not named and not plain then
    focus_tree(tree)
    return
  end
  vim.api.nvim_set_current_win(tree.winid)
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  unlock(win)
  if named then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  else
    vim.api.nvim_win_set_buf(win, buf)
  end
end

function M.file_at(tree)
  if not tree then
    return nil
  end
  if valid_win(tree.winid) and vim.api.nvim_get_current_win() == tree.winid then
    local row = vim.api.nvim_win_get_cursor(tree.winid)[1]
    local node = (tree.visible_nodes or {})[row]
    if node and node.type == "file" and node.path and node.path ~= "" then
      return node.path
    end
  end
  if tree._bsi_file and tree._bsi_file ~= "" then
    return tree._bsi_file
  end
  if tree._git_selected and tree._git_selected ~= "" then
    return tree._git_selected
  end
end

function M.open_in_tree(tree)
  if not tree then
    return
  end
  local path = M.file_at(tree)
  if not path or path == "" then
    return
  end
  local full = vim.fn.fnamemodify(path, ":p")
  full = full:gsub("/+$", "")
  path = vim.fn.resolve(full)
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  local exists = stat and stat.type == "file"
  tree._git_gen = (tree._git_gen or 0) + 1
  tree.git_view = false
  tree._git_selected = nil
  tree._bsi_file = nil
  unmap_tree(tree)
  M.close(tree)
  tree._bsi_saved_buf = nil
  tree._bsi_saved_path = nil
  tree:refresh()
  if not exists then
    focus_tree(tree)
    return
  end
  show_saved(tree, nil, path)
  local tree_mod = require("bsi.ui.tree")
  tree_mod.set_opened_buffer(vim.api.nvim_get_current_buf())
  tree._visible_dirty = true
  tree:render()
  tree:find_file(path)
end

function M.quit(tree)
  if not tree then
    return
  end
  local path = tree._bsi_saved_path
  local buf = tree._bsi_saved_buf
  tree._git_gen = (tree._git_gen or 0) + 1
  tree.git_view = false
  unmap_tree(tree)
  M.close(tree)
  tree._bsi_saved_buf = nil
  tree._bsi_saved_path = nil
  tree:refresh()
  show_saved(tree, buf, path)
end

function M.leave(tree)
  if not tree then
    return
  end
  local path = tree._bsi_saved_path
  local buf = tree._bsi_saved_buf
  tree._git_gen = (tree._git_gen or 0) + 1
  tree.git_view = false
  unmap_tree(tree)
  M.close(tree)
  tree._bsi_saved_buf = nil
  tree._bsi_saved_path = nil
  show_saved(tree, buf, path)
end

function M.show(tree, abs_path)
  if not tree or not abs_path or abs_path == "" or not valid_win(tree.winid) then
    return
  end
  tree._bsi_file = abs_path
  if not ensure(tree) then
    return
  end
  clear_editor(tree)
  place(tree)
  tree._bsi_gen = (tree._bsi_gen or 0) + 1
  local gen = tree._bsi_gen
  local rel = repo_rel(tree.root_path, abs_path)
  local work = read_disk(abs_path)
  local root = tree.root_path
  vim.system({ "git", "-C", root, "--no-optional-locks", "show", "HEAD:" .. rel }, { text = true }, function(obj)
    vim.schedule(function()
      if gen ~= tree._bsi_gen then
        return
      end
      if not side_ok(tree, tree._bsi_a, tree._bsi_a_buf, "a") or not side_ok(tree, tree._bsi_b, tree._bsi_b_buf, "b") then
        return
      end
      local head = (obj and obj.code == 0) and (obj.stdout or "") or ""
      local hunks = diff_indices(head, work or "")
      tree._bsi_hunks = hunks
      fill(tree._bsi_a_buf, work or "", abs_path)
      fill(tree._bsi_b_buf, head, abs_path)
      paint(tree._bsi_a, " BsiDiffViewPanel  WORK  " .. rel)
      paint(tree._bsi_b, " BsiDiffViewPanel  HEAD  " .. rel)
      sync_diff(tree._bsi_a)
      sync_diff(tree._bsi_b)
      local head_line, work_line = 1, 1
      if hunks[1] then
        head_line, work_line = M.change_lines(hunks[1])
      end
      align_change(tree, head_line, work_line)
      apply_width(tree)
      focus_tree(tree)
    end)
  end)
end

return M
