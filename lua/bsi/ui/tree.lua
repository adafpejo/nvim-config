-- lua/bsi/tree.lua
-- Modern BSI Tree: clean architecture for embedded file tree rendering

local M = {}

M.instances = {}

local has_devicons, devicons = pcall(require, "nvim-web-devicons")

---@class bsi.Node
---@field id string
---@field name string
---@field path string
---@field type "file"|"directory"|"root"
---@field depth integer
---@field expanded boolean
---@field children bsi.Node[]|nil
---@field git_status string|nil

---@class bsi.TreeState
---@field root bsi.Node
---@field expanded table<string,boolean>

---@class bsi.Renderer
local Renderer = {}
Renderer.__index = Renderer

function Renderer.new()
  return setmetatable({}, Renderer)
end

---@param bufnr integer
---@param nodes bsi.Node[]
---@param winid integer|nil
function Renderer:render(bufnr, nodes, winid)
  local lines = {}
  local highlights = {}

  -- Get current active file path to highlight it
  local current_file = ""
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      current_file = vim.api.nvim_buf_get_name(buf)
      break
    end
  end

  for i, node in ipairs(nodes) do
    local indent = string.rep(" ", node.depth)
    local prefix = "   "
    local arrow = "  "
    local icon = ""
    local icon_hl = nil
    local name_hl = nil
    local status_hl = nil
    local git_status_prefix = ""

    local is_current = node.path == current_file
    -- local is_opened = vim.fn.bufloaded(node.path) ~= 0 -- Removed highlighted opened files feature

    -- Handle Git status effects
    local gs = node.git_status
    if gs then
      local staged = gs:sub(1, 1)
      local unstaged = gs:sub(2, 2)

      if gs == "??" then
        status_hl = "DiagnosticWarn"
        git_status_prefix = "?"
      elseif staged == "A" then
        status_hl = "DiagnosticOk"
        name_hl = "DiagnosticOk"
        git_status_prefix = "A"
      elseif staged == "M" or staged == "R" or staged == "C" then
        status_hl = "DiagnosticOk"
        name_hl = "DiagnosticOk"
        git_status_prefix = staged
      elseif staged == "D" then
        status_hl = "DiagnosticError"
        name_hl = "DiagnosticError"
        git_status_prefix = "D"
      elseif unstaged == "M" then
        status_hl = "DiagnosticWarn"
        name_hl = "DiagnosticWarn"
        git_status_prefix = "M"
      elseif unstaged == "D" then
        status_hl = "DiagnosticError"
        name_hl = "DiagnosticError"
        git_status_prefix = "D"
      elseif gs == "DIR_ADDED" then
        git_status_prefix = "A"
        name_hl = "DiagnosticOk"
        status_hl = "DiagnosticOk"
      elseif gs == "DIR_PARTIAL" then
        git_status_prefix = "M"
        name_hl = "DiagnosticWarn"
        status_hl = "DiagnosticWarn"
      elseif gs == "DIR_UNTRACKED" then
        git_status_prefix = "?"
        name_hl = "DiagnosticWarn"
        status_hl = "DiagnosticWarn"
      elseif gs:sub(1, 10) == "DIR_MULTI:" then
        git_status_prefix = gs:sub(11)
        name_hl = "DiagnosticWarn"
        status_hl = "DiagnosticWarn"
      end
    end

    if node.type == "root" or node.type == "directory" then
      if node.expanded then
        if node.children and #node.children == 0 then
          icon = " " -- Empty/Border only
        else
          icon = " " -- Open
        end
        arrow = " "
      else
        icon = " " -- Closed
        arrow = " "
      end
      name_hl = name_hl or "Directory"
    else
      arrow = "  "
      if has_devicons then
        local ic, hl = devicons.get_icon(node.name, vim.fn.fnamemodify(node.name, ":e"), { default = true })
        icon = ic .. " "
        icon_hl = hl
      else
        icon = " "
      end
    end

    local base_content = indent .. prefix .. arrow .. icon .. node.name

    -- Fixed column for git status
    local status_col = 34
    local status_text = git_status_prefix
    local line_content = base_content
    if status_text ~= "" then
      local padding = status_col - #base_content
      if padding > 0 then
        line_content = base_content .. string.rep(" ", padding) .. status_text
      else
        line_content = base_content .. " " .. status_text
      end
    end

    table.insert(lines, line_content)

    if is_current then
      table.insert(highlights, { hl = "BSITreeCurrentFile", line = i - 1, col_start = 0, col_end = -1 })
    end

    local current_col = #indent
    if prefix ~= "" then
      current_col = current_col + #prefix
    end

    local arrow_start = current_col
    local arrow_end = arrow_start + #arrow

    local icon_start = arrow_end
    local icon_end = icon_start + #icon

    if icon_hl then
      table.insert(highlights, { hl = icon_hl, line = i - 1, col_start = icon_start, col_end = icon_end })
    end

    if name_hl then
      table.insert(highlights, { hl = name_hl, line = i - 1, col_start = icon_end, col_end = icon_end + #node.name })
    end

    if status_text ~= "" then
      local status_start = #line_content - #status_text
      table.insert(highlights, { hl = status_hl or "Normal", line = i - 1, col_start = status_start, col_end = -1 })
    end
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace("bsitree")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(bufnr, ns, hl.hl, hl.line, hl.col_start, hl.col_end)
  end

  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "Tree"

  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_option_value("number", false, { win = winid })
    vim.api.nvim_set_option_value("relativenumber", false, { win = winid })
  end
end

---@class bsi.Provider
local Provider = {}
Provider.__index = Provider

local DEFAULT_IGNORE = { "node_modules$", "%.git$", "^vendor$", "^dist$", "^build$", "^target$" }

function Provider.new() return setmetatable({}, Provider) end

function Provider:_get_git_changes(root)
  root = root:gsub("/$", "")
  local git_root_cmd = "git -C " .. vim.fn.shellescape(root) .. " rev-parse --show-toplevel 2>/dev/null"
  local handle_root = io.popen(git_root_cmd)
  if not handle_root then return nil end
  local git_root = handle_root:read("*l")
  handle_root:close()
  if not git_root or git_root == "" then return nil end

  local cmd = "git -C " .. vim.fn.shellescape(git_root) .. " status --porcelain"
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()

  if result == "" then return nil end

  local changes = {}
  changes[root] = { status = "dir" }

  for line in result:gmatch("[^\r\n]+") do
    local status = line:sub(1, 2)
    local path = line:sub(4)
    if path:match('^"') then path = path:match('^"(.*)"$') end
    if path:match(" %-> ") then path = vim.split(path, " -> ")[2] end

    local fullpath = (git_root .. "/" .. path):gsub("/$", "")

    -- Check if it's an untracked directory
    if status == "??" and vim.fn.isdirectory(fullpath) == 1 then
        -- We need to list all files in this untracked directory and mark them as untracked
        local function mark_untracked(p)
            changes[p] = { status = "??" }
            local h = vim.loop.fs_scandir(p)
            if h then
                while true do
                    local name, type = vim.loop.fs_scandir_next(h)
                    if not name then break end
                    local fp = p .. "/" .. name
                    if type == "directory" then
                        mark_untracked(fp)
                    else
                        changes[fp] = { status = "??" }
                    end
                end
            end
        end
        mark_untracked(fullpath)
    else
        if fullpath == root or fullpath:sub(1, #root + 1) == root .. "/" then
          changes[fullpath] = { status = status }
          local current = fullpath
          while #current > #root do
            current = vim.fn.fnamemodify(current, ":h")
            if not changes[current] then changes[current] = { status = "dir" }
            elseif changes[current].status ~= "dir" then break end
            if current == root then break end
          end
        end
    end
  end
  return changes
end

function Provider:_should_ignore(name)
  for _, pattern in ipairs(DEFAULT_IGNORE) do
    if name:match(pattern) then return true end
  end
  return false
end

function Provider:scan(path, depth, opts)
  depth = depth or 0
  opts = opts or {}
  local git_changes = opts.git_changes
  local git_only = opts.git_only

  if git_only and git_changes and not git_changes[path] then return nil end

  local node_gs = (git_changes and git_changes[path] and git_changes[path].status ~= "dir") and git_changes[path].status or nil

  local node = {
    id = path,
    name = vim.fn.fnamemodify(path, ":t") or path,
    path = path,
    type = depth == 0 and "root" or "directory",
    depth = depth,
    expanded = opts.expand_all or (depth < 2),
    children = {},
    git_status = node_gs,
  }

  local children_map = {}
  local handle = vim.loop.fs_scandir(path)
  if handle then
    while true do
      local name = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if not self:_should_ignore(name) then children_map[name] = true end
    end
  end

  if git_changes then
    for fullpath, info in pairs(git_changes) do
      if info.status == "??" or info.status:sub(1,1) == "D" or info.status:sub(2,2) == "D" then
        local parent = vim.fn.fnamemodify(fullpath, ":h")
        if parent == path then
          local name = vim.fn.fnamemodify(fullpath, ":t")
          if not children_map[name] or info.status:match("D") then
            children_map[name] = info.status == "??" and "untracked" or "deleted"
          end
        end
      end
    end
  end

  for name, state in pairs(children_map) do
    local fullpath = path .. "/" .. name
    if git_only and git_changes and not git_changes[fullpath] then goto continue end

    local is_dir = false
    if state == "deleted" then is_dir = false
    else
      local stat = vim.loop.fs_lstat(fullpath)
      if not stat then goto continue end
      is_dir = stat.type == "directory"
    end

    local g_status = git_changes and git_changes[fullpath] and git_changes[fullpath].status
    local child
    if is_dir then
      child = self:scan(fullpath, depth + 1, opts)
      if child then
        if git_only and #child.children == 0 then goto continue end
        child.expanded = opts.expand_all or (depth < 1)
      else goto continue end
    else
      child = { id = fullpath, name = name, path = fullpath, type = "file", depth = depth + 1, expanded = false, children = nil, git_status = g_status ~= "dir" and g_status or nil }
    end
    table.insert(node.children, child)
    ::continue::
  end

  if git_changes and node.type == "directory" then
    local all_staged, some_staged, some_unstaged, all_untracked = true, false, false, true
    for _, c in ipairs(node.children) do
      local s = c.git_status
      if s then
        if s == "DIR_ADDED" then some_staged = true; all_untracked = false
        elseif s == "DIR_PARTIAL" then some_unstaged = true; all_staged = false; all_untracked = false
        elseif s == "DIR_UNTRACKED" then some_unstaged = true; all_staged = false
        else
          local staged = s:sub(1,1)
          local unstaged = s:sub(2,2)
          if staged ~= "?" then all_untracked = false end
          if staged ~= " " and staged ~= "?" then some_staged = true end
          if unstaged ~= " " or staged == "?" then some_unstaged = true; all_staged = false end
        end
      else
        if c.type == "file" then all_staged = false; all_untracked = false end
        all_untracked = false
      end
    end
    if all_untracked and some_unstaged then node.git_status = "DIR_UNTRACKED"
    elseif all_staged and some_staged then node.git_status = "DIR_ADDED"
    elseif some_staged or some_unstaged then
      -- Collect all unique status characters from children
      local statuses = {}
      local chars = {}
      local function add_status(s)
        if not s then return end
        if s == "DIR_ADDED" then s = "A"
        elseif s == "DIR_PARTIAL" then s = "M"
        elseif s == "DIR_UNTRACKED" then s = "?"
        end
        for j = 1, #s do
          local char = s:sub(j, j)
          if char ~= " " and not statuses[char] then
            statuses[char] = true
            table.insert(chars, char)
          end
        end
      end
      for _, c in ipairs(node.children) do add_status(c.git_status) end
      table.sort(chars)
      node.git_status = "DIR_MULTI:" .. table.concat(chars, "")
    end
  end

  table.sort(node.children, function(a, b)
    if a.type ~= b.type then return a.type == "directory" end
    return a.name:lower() < b.name:lower()
  end)

  if node.type == "directory" and #node.children == 1 and node.children[1].type == "directory" then
    local child = node.children[1]
    node.name = node.name .. "/" .. child.name
    node.children = child.children
    node.path = child.path
    node.id = child.id
    node.git_status = child.git_status
    local function sync_depth(n, d)
      n.depth = d
      if n.children then for _, c in ipairs(n.children) do sync_depth(c, d + 1) end end
    end
    if node.children then for _, c in ipairs(node.children) do sync_depth(c, node.depth + 1) end end
  end
  return node
end

---@class bsi.Tree
local Tree = {}
Tree.__index = Tree

function Tree.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Tree)
  self.provider = Provider.new()
  self.renderer = Renderer.new()
  self.root_path = opts.root or vim.fn.getcwd()
  self.opts = opts
  local scan_opts = { expand_all = opts.expand_all, git_only = opts.git_only }
  scan_opts.git_changes = self.provider:_get_git_changes(self.root_path)
  local root_node = self.provider:scan(self.root_path, 0, scan_opts)
  self.state = { root = root_node or { id = self.root_path, name = vim.fn.fnamemodify(self.root_path, ":t"), path = self.root_path, type = "root", depth = 0, expanded = true, children = {} } }
  self.bufnr = opts.bufnr
  self.winid = opts.winid
  return self
end

function Tree:get_root_path() return vim.fn.fnamemodify(self.root_path, ":~") end

function Tree:get_visible_nodes()
  local nodes = {}
  local function walk(node)
    if node.type ~= "root" then table.insert(nodes, node) end
    if (node.type == "directory" or node.type == "root") and node.expanded and node.children then
      for _, child in ipairs(node.children) do walk(child) end
    end
  end
  walk(self.state.root)
  return nodes
end

function Tree:render()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end
  self.visible_nodes = self:get_visible_nodes()
  local render_nodes = {}
  for _, node in ipairs(self.visible_nodes) do
    local n = vim.deepcopy(node)
    n.depth = n.depth - 1
    table.insert(render_nodes, n)
  end
  self.renderer:render(self.bufnr, render_nodes, self.winid)
end

function Tree:open()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    self.bufnr = vim.api.nvim_create_buf(false, true)
  end
  local is_new_win = false
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    vim.cmd("leftabove vsplit")
    self.winid = vim.api.nvim_get_current_win()
    is_new_win = true
  end
  vim.api.nvim_win_set_buf(self.winid, self.bufnr)
  vim.b[self.bufnr].bsi_tree_root = self.root_path

  -- Register instance
  M.instances[self.bufnr] = self
  pcall(vim.api.nvim_buf_set_name, self.bufnr, "GitView: Tree")

  if is_new_win then vim.api.nvim_win_set_width(self.winid, 40) end
  self:render()

  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = self.bufnr, silent = true, desc = "Tree: " .. desc })
  end

  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = self.bufnr,
    callback = function()
      M.instances[self.bufnr] = nil
    end,
  })

  map("R", function() self:refresh() end, "Refresh")
  map("q", "<cmd>close<cr>", "Close")
  map("<CR>", function() self:toggle() end, "Toggle / Expand directory")
  map("o", function() self:_open_file() end, "Open file")
  map("d", function() self:_diff_file() end, "Diff file")
  map("y", function() self:_yank(false) end, "Yank name")
  map("Y", function() self:_yank(true) end, "Yank relative path")
  map("<LeftMouse>", "<LeftMouse>", "Move cursor")
  map("<LeftRelease>", function() self:toggle() end, "Click to toggle/open")
  map("<2-LeftMouse>", function() self:toggle() end, "Double click to toggle/open")
end

function Tree:refresh()
  local expanded = {}
  local function collect(node)
    if node.expanded then expanded[node.id] = true end
    if node.children then for _, child in ipairs(node.children) do collect(child) end end
  end
  collect(self.state.root)
  local scan_opts = { expand_all = self.opts.expand_all, git_only = self.opts.git_only }
  scan_opts.git_changes = self.provider:_get_git_changes(self.root_path)
  local new_root = self.provider:scan(self.root_path, 0, scan_opts)
  new_root = new_root or { id = self.root_path, name = vim.fn.fnamemodify(self.root_path, ":t"), path = self.root_path, type = "root", depth = 0, expanded = true, children = {} }
  local function restore(node)
    if expanded[node.id] or scan_opts.expand_all then
      node.expanded = true
      if node.children then for _, child in ipairs(node.children) do restore(child) end end
    end
  end
  restore(new_root)
  self.state.root = new_root
  self:render()
end

function Tree:toggle()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
  if not node or node.type == "file" then self:_open_file() return end
  if not node.expanded and node.type == "directory" and node.children and #node.children == 0 then
    local scanned = self.provider:scan(node.path, node.depth)
    node.children = scanned.children
  end
  node.expanded = not node.expanded
  self:render()
end

function Tree:_open_file()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
  if not node or node.type ~= "file" then return end
  vim.cmd("wincmd l")
  vim.cmd("edit " .. vim.fn.fnameescape(node.path))
end

function Tree:_diff_file()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
  if not node or node.type ~= "file" then return end
  vim.cmd("DiffviewOpen -- " .. vim.fn.fnameescape(node.path))
end

function Tree:_yank(full)
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node then return end
  local text = full and (node.path:sub(#self.root_path + 2)) or node.name
  if text == "" then text = "." end
  vim.fn.setreg('"', text)
  print("tree: Yanked " .. text)
  vim.schedule(function() vim.fn.setreg("+", text) end)
end

function Tree:find_file(target_path)
  if not target_path or target_path == "" then return end
  if target_path:sub(1, #self.root_path) ~= self.root_path then return end

  local function expand_recursive(node, target)
    if node.path == target then return true end
    if node.type == "directory" or node.type == "root" then
      if target:sub(1, #node.path) == node.path then
        if not node.expanded then
          if node.children and #node.children == 0 then
             local scanned = self.provider:scan(node.path, node.depth, self.opts)
             node.children = scanned.children
          end
          node.expanded = true
        end
        if node.children then
          for _, child in ipairs(node.children) do
            if expand_recursive(child, target) then return true end
          end
        end
      end
    end
    return false
  end

  expand_recursive(self.state.root, target_path)
  self:render()

  for i, node in ipairs(self.visible_nodes) do
    if node.path == target_path then
      if self.winid and vim.api.nvim_win_is_valid(self.winid) then
        vim.api.nvim_win_set_cursor(self.winid, { i, 0 })
      end
      break
    end
  end
end

function M.new(opts) return Tree.new(opts) end
function M.get_root_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.b[bufnr].bsi_tree_root
end

function M.toggle_tree()
  local found_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "Tree" then
      found_win = win
      break
    end
  end

  if found_win then
    vim.api.nvim_win_close(found_win, true)
  else
    M.new():open()
  end
end

function M.setup()
  vim.api.nvim_set_hl(0, "BSITreeCurrentFile", { bg = "#3b4261", bold = true })
  vim.api.nvim_set_hl(0, "BSITreeOpenedFile", { fg = "#7aa2f7", italic = true })

  local group = vim.api.nvim_create_augroup("BSITreeTracking", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if path == "" then return end
      for _, tree in pairs(M.instances) do
        if tree.winid and vim.api.nvim_win_is_valid(tree.winid) then
          tree:find_file(path)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function()
      for _, tree in pairs(M.instances) do tree:render() end
    end,
  })

  vim.api.nvim_create_user_command("BSITree", function(args)
    local root = args.args ~= "" and args.args or nil
    M.new({ root = root }):open()
  end, { nargs = "?", complete = "dir" })
  vim.keymap.set("n", "<leader>et", function() M.toggle_tree() end, { desc = "Toggle BSI Tree" })
end

return M
