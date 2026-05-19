-- lua/bsi/tree.lua
-- Modern BSI Tree: clean architecture for embedded file tree rendering

local M = {}

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

  for i, node in ipairs(nodes) do
    local indent = string.rep("  ", node.depth)
    local prefix = "   "
    local icon = ""
    local icon_hl = nil
    local name_hl = nil
    local prefix_hl = nil

    -- Handle Git status effects
    local gs = node.git_status
    if gs then
      if gs == "??" then
        prefix = "?? "
        prefix_hl = "DiagnosticWarn"
      elseif gs:match("D") then
        prefix = "D  "
        prefix_hl = "DiagnosticError"
        name_hl = "DiagnosticError"
      elseif gs:sub(1,1) == "A" then
        prefix = "A  "
        prefix_hl = "DiagnosticOk"
        name_hl = "DiagnosticOk"
      elseif gs:match("M") then
        prefix = "M  "
        prefix_hl = "DiagnosticWarn"
        name_hl = "DiagnosticWarn"
      elseif gs == "DIR_ADDED" then
        prefix = "   "
        name_hl = "DiagnosticOk"
      elseif gs == "DIR_PARTIAL" then
        prefix = "   "
        name_hl = "DiagnosticWarn"
      end
    else
      prefix = "   "
    end

    if node.type == "root" or node.type == "directory" then
      if node.expanded then
        if node.children and #node.children == 0 then
          icon = " " -- Empty/Border only
        else
          icon = " " -- Open
        end
      else
        icon = " " -- Closed
      end
      name_hl = name_hl or "Directory"
    else
      if has_devicons then
        local ic, hl = devicons.get_icon(node.name, vim.fn.fnamemodify(node.name, ":e"), { default = true })
        icon = ic .. " "
        icon_hl = hl
      else
        icon = " "
      end
    end

    local line_content = indent .. prefix .. icon .. node.name
    table.insert(lines, line_content)

    local current_col = #indent
    if prefix ~= "" then
      if prefix_hl then
        table.insert(highlights, { hl = prefix_hl, line = i - 1, col_start = current_col, col_end = current_col + #prefix })
      end
      current_col = current_col + #prefix
    end

    local icon_start = current_col
    local icon_end = icon_start + #icon

    if icon_hl then
      table.insert(highlights, { hl = icon_hl, line = i - 1, col_start = icon_start, col_end = icon_end })
    end
    if name_hl then
      table.insert(highlights, { hl = name_hl, line = i - 1, col_start = icon_end, col_end = -1 })
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
  vim.bo[bufnr].filetype = "bsitree"

  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_option_value("number", false, { win = winid })
    vim.api.nvim_set_option_value("relativenumber", false, { win = winid })
  end
end

---@class bsi.Provider
local Provider = {}
Provider.__index = Provider

--- Default ignore patterns
local DEFAULT_IGNORE = {
  "node_modules$",
  "%.git$",
  "^vendor$",
  "^dist$",
  "^build$",
  "^target$",
}

function Provider.new()
  return setmetatable({}, Provider)
end

--- Get list of files with uncommitted changes
---@param root string
---@return table<string, {status: string}>|nil
function Provider:_get_git_changes(root)
  root = root:gsub("/$", "")

  -- Find git root
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
  -- Root of the search should always be considered a directory
  changes[root] = { status = "dir" }

  for line in result:gmatch("[^\r\n]+") do
    local status = line:sub(1, 2)
    local path = line:sub(4)

    -- Handle quoted paths
    if path:match('^"') then
      path = path:match('^"(.*)"$')
    end

    if path:match(" %-> ") then
      local parts = vim.split(path, " -> ")
      path = parts[#parts]
    end

    local fullpath = git_root .. "/" .. path
    -- Normalize path (remove trailing slash for directories)
    fullpath = fullpath:gsub("/$", "")

    -- Only process if it's within our tree root
    if fullpath == root or fullpath:sub(1, #root + 1) == root .. "/" then
      changes[fullpath] = { status = status }

      -- Mark all parent directories up to the search root
      local current = fullpath
      while #current > #root do
        current = vim.fn.fnamemodify(current, ":h")
        if not changes[current] then
          changes[current] = { status = "dir" }
        elseif changes[current].status ~= "dir" then
          -- If it was already marked as a file change, we keep the file change
          break
        end
        if current == root then break end
      end
    end
  end
  return changes
end

--- Check if a name should be ignored
---@param name string
---@return boolean
function Provider:_should_ignore(name)
  for _, pattern in ipairs(DEFAULT_IGNORE) do
    if name:match(pattern) then
      return true
    end
  end
  return false
end

--- Scan a directory and build node tree (lazy: one level at a time)
---@param path string
---@param depth integer
---@param opts table|nil
---@return bsi.Node|nil
function Provider:scan(path, depth, opts)
  depth = depth or 0
  opts = opts or {}
  local git_changes = opts.git_changes
  local git_only = opts.git_only

  if git_only and git_changes and not git_changes[path] then
    return nil
  end

  local node = {
    id = path,
    name = vim.fn.fnamemodify(path, ":t") or path,
    path = path,
    type = depth == 0 and "root" or "directory",
    depth = depth,
    expanded = opts.expand_all or (depth < 2),
    children = {},
    git_status = (git_changes and git_changes[path] and git_changes[path].status ~= "dir") and git_changes[path].status or nil,
  }

  -- 1. Get physical children
  local children_map = {}
  local handle = vim.loop.fs_scandir(path)
  if handle then
    while true do
      local name = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if not self:_should_ignore(name) then
        children_map[name] = true
      end
    end
  end

  -- 2. Add deleted files from git_changes that are in this directory
  if git_changes then
    for fullpath, info in pairs(git_changes) do
      if info.status:match("D") then
        local parent = vim.fn.fnamemodify(fullpath, ":h")
        if parent == path then
          local name = vim.fn.fnamemodify(fullpath, ":t")
          children_map[name] = "deleted"
        end
      end
    end
  end

  -- 3. Process all collected children
  for name, state in pairs(children_map) do
    local fullpath = path .. "/" .. name
    if git_only and git_changes and not git_changes[fullpath] then
      goto continue
    end

    local is_dir = false
    local is_deleted = state == "deleted"

    if is_deleted then
      is_dir = false
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
        if git_only and #child.children == 0 then
          goto continue
        end
        child.expanded = opts.expand_all or (depth < 1)
      else
        goto continue
      end
    else
      child = {
        id = fullpath,
        name = name,
        path = fullpath,
        type = "file",
        depth = depth + 1,
        expanded = false,
        children = nil,
        git_status = g_status ~= "dir" and g_status or nil,
      }
    end

    table.insert(node.children, child)
    ::continue::
  end

  -- Calculate directory git status based on children
  if git_changes and node.type == "directory" then
    local all_added = true
    local some_added = false
    local some_modified = false

    for _, c in ipairs(node.children) do
      local s = c.git_status
      if s then
        if s:sub(1, 1) == "A" or s == "DIR_ADDED" then
          some_added = true
        else
          all_added = false
        end
        some_modified = true
      else
        if c.type == "file" then
          all_added = false
        end
        all_added = false
      end
    end

    if all_added and some_added then
      node.git_status = "DIR_ADDED"
    elseif some_added or some_modified then
      node.git_status = "DIR_PARTIAL"
    end
  end

  table.sort(node.children, function(a, b)
    if a.type ~= b.type then
      return a.type == "directory"
    end
    return a.name:lower() < b.name:lower()
  end)

  -- Compact directories
  if node.type == "directory" and #node.children == 1 and node.children[1].type == "directory" then
    local child = node.children[1]
    node.name = node.name .. "/" .. child.name
    node.children = child.children
    node.path = child.path
    node.id = child.id
    node.git_status = child.git_status

    local function sync_depth(n, d)
      n.depth = d
      if n.children then
        for _, c in ipairs(n.children) do
          sync_depth(c, d + 1)
        end
      end
    end
    if node.children then
      for _, c in ipairs(node.children) do
        sync_depth(c, node.depth + 1)
      end
    end
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

function Tree:get_root_path()
  return vim.fn.fnamemodify(self.root_path, ":~")
end

function Tree:get_visible_nodes()
  local nodes = {}
  local function walk(node)
    -- Skip the root node itself
    if node.type ~= "root" then
      table.insert(nodes, node)
    end
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
  
  -- Correct depth of sub-root nodes for rendering
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
  if is_new_win then vim.api.nvim_win_set_width(self.winid, 40) end
  self:render()
  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = self.bufnr, silent = true, desc = "Tree: " .. desc })
  end
  map("R", function() self:refresh() end, "Refresh")
  map("q", "<cmd>close<cr>", "Close")
  map("<CR>", function() self:toggle() end, "Toggle / Expand directory")
  map("o", function() self:_open_file() end, "Open file")
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

function Tree:_yank(full)
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node then return end

  local text = full and (node.path:sub(#self.root_path + 2)) or node.name
  if text == "" then text = "." end

  vim.fn.setreg('"', text)
  print("tree: Yanked " .. text)
  
  vim.schedule(function()
    vim.fn.setreg("+", text)
  end)
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
  if is_new_win then vim.api.nvim_win_set_width(self.winid, 40) end
  self:render()
  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = self.bufnr, silent = true, desc = "Tree: " .. desc })
  end
  map("R", function() self:refresh() end, "Refresh")
  map("q", "<cmd>close<cr>", "Close")
  map("<CR>", function() self:toggle() end, "Toggle / Expand directory")
  map("o", function() self:_open_file() end, "Open file")
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
  local nodes = self:get_visible_nodes()
  if #nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = nodes[idx]
  if not node or node.type == "file" then self:_open_file() return end
  if not node.expanded and node.type == "directory" and node.children and #node.children == 0 then
    local scanned = self.provider:scan(node.path, node.depth)
    node.children = scanned.children
  end
  node.expanded = not node.expanded
  self:render()
end

function Tree:_open_file()
  local nodes = self:get_visible_nodes()
  if #nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = nodes[idx]
  if not node or node.type ~= "file" then return end
  vim.cmd("wincmd l")
  vim.cmd("edit " .. vim.fn.fnameescape(node.path))
end

local function log(fmt, ...)
  vim.notify(string.format("tree: " .. fmt, ...))
end

function Tree:_yank(full)
  local nodes = self:get_visible_nodes()
  if #nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = nodes[cursor[1]]
  if not node then return end

  local text
  if full then
    -- Path relative to the root_path
    text = node.path:sub(#self.root_path + 2)
    if text == "" then text = "." end
  else
    text = node.name
  end

  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.api.nvim_echo({{ "tree: Yanked " .. text, "Normal" }}, false, {})
end

function M.new(opts) return Tree.new(opts) end
function M.get_root_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.b[bufnr].bsi_tree_root
end

function M.setup()
  vim.api.nvim_create_user_command("BSITree", function(args)
    local root = args.args ~= "" and args.args or nil
    M.new({ root = root }):open()
  end, { nargs = "?", complete = "dir" })
  vim.keymap.set("n", "<leader>tt", function() M.new():open() end, { desc = "Open BSI Tree" })
end

return M
