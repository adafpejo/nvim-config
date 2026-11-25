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
  end)
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
  drop_win(tree._bsi_a)
  drop_win(tree._bsi_b)
  tree._bsi_a = nil
  tree._bsi_b = nil
  tree._bsi_a_buf = nil
  tree._bsi_b_buf = nil
end

local function arm_quit(tree, buf)
  vim.keymap.set("n", "q", function()
    M.quit(tree)
  end, { buffer = buf, silent = true, nowait = true, desc = "Close BsiDiffViewPanel" })
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
  vim.wo[win].scrollbind = true
  vim.wo[win].cursorbind = true
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = win })
  arm_quit(tree, buf)
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
  pcall(vim.keymap.del, "n", "j", { buffer = tree.bufnr })
  pcall(vim.keymap.del, "n", "k", { buffer = tree.bufnr })
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

function M.show(tree, abs_path)
  if not tree or not abs_path or abs_path == "" or not valid_win(tree.winid) then
    return
  end
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
      fill(tree._bsi_a_buf, head, abs_path)
      fill(tree._bsi_b_buf, work or "", abs_path)
      paint(tree._bsi_a, " BsiDiffViewPanel  HEAD  " .. rel)
      paint(tree._bsi_b, " BsiDiffViewPanel  WORK  " .. rel)
      sync_diff(tree._bsi_a)
      sync_diff(tree._bsi_b)
      if valid_win(tree._bsi_b) then
        pcall(vim.api.nvim_win_set_cursor, tree._bsi_b, { 1, 0 })
      end
      focus_tree(tree)
    end)
  end)
end

return M
