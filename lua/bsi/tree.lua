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
    local icon = ""
    local icon_hl = nil
    local name_hl = nil

    if node.type == "root" or node.type == "directory" then
      icon = node.expanded and " " or " "
      name_hl = "Directory"
    else
      if has_devicons then
        local ic, hl = devicons.get_icon(node.name, vim.fn.fnamemodify(node.name, ":e"), { default = true })
        icon = ic .. " "
        icon_hl = hl
      else
        icon = " "
      end
    end

    table.insert(lines, indent .. icon .. node.name)
    
    local icon_start = #indent
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
---@return bsi.Node
function Provider:scan(path, depth)
  depth = depth or 0
  if depth > 5 then
    return { id = path, name = vim.fn.fnamemodify(path, ":t"), path = path, type = "directory", depth = depth, expanded = false, children = {} }
  end

  local node = {
    id = path,
    name = vim.fn.fnamemodify(path, ":t") or path,
    path = path,
    type = depth == 0 and "root" or "directory",
    depth = depth,
    expanded = depth < 2, -- expand first 2 levels by default
    children = {},
  }

  local handle = vim.loop.fs_scandir(path)
  if not handle then
    return node
  end

  while true do
    local name = vim.loop.fs_scandir_next(handle)
    if not name then
      break
    end

    if self:_should_ignore(name) then
      goto continue
    end

    local fullpath = path .. "/" .. name
    local stat = vim.loop.fs_lstat(fullpath)
    if not stat then
      goto continue
    end

    local is_dir = stat.type == "directory"

    local child = {
      id = fullpath,
      name = name,
      path = fullpath,
      type = is_dir and "directory" or "file",
      depth = depth + 1,
      expanded = false,
      children = is_dir and {} or nil,
    }

    -- Eagerly populate only the first 2 levels
    if is_dir and depth < 2 then
      child.children = self:scan(fullpath, depth + 1).children
      child.expanded = true
    end

    table.insert(node.children, child)
    ::continue::
  end

  table.sort(node.children, function(a, b)
    if a.type ~= b.type then
      return a.type == "directory"
    end
    return a.name:lower() < b.name:lower()
  end)

  return node
end

---@class bsi.Tree
local Tree = {}
Tree.__index = Tree

---@param opts table|nil
function Tree.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Tree)

  self.provider = Provider.new()
  self.renderer = Renderer.new()

  self.root_path = opts.root or vim.fn.getcwd()

  local root_node = self.provider:scan(self.root_path, 0)
  self.state = { root = root_node }

  self.bufnr = opts.bufnr
  self.winid = opts.winid

  return self
end

--- Flatten tree into visible lines (only expanded nodes)
---@return bsi.Node[]
function Tree:get_visible_nodes()
  local nodes = {}

  local function walk(node)
    table.insert(nodes, node)
    if (node.type == "directory" or node.type == "root") and node.expanded and node.children then
      for _, child in ipairs(node.children) do
        walk(child)
      end
    end
  end

  walk(self.state.root)
  return nodes
end

--- Render current state into the buffer
function Tree:render()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end
  local nodes = self:get_visible_nodes()
  self.renderer:render(self.bufnr, nodes, self.winid)
end

--- Open the tree in a window
function Tree:open()
  -- Reuse or create buffer
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    local name = "BSI-Tree: " .. vim.fn.fnamemodify(self.root_path, ":t")
    local existing = vim.fn.bufnr(name)
    if existing ~= -1 then
      self.bufnr = existing
    else
      self.bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(self.bufnr, name)
    end
  end

  -- Open in sidebar if no window assigned
  local is_new_win = false
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    vim.cmd("leftabove vsplit")
    self.winid = vim.api.nvim_get_current_win()
    is_new_win = true
  end

  vim.api.nvim_win_set_buf(self.winid, self.bufnr)

  -- Set window width only if newly created
  if is_new_win then
    vim.api.nvim_win_set_width(self.winid, 80)
  end

  self:render()

  -- Keymaps on the tree buffer
  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = self.bufnr, silent = true, desc = "Tree: " .. desc })
  end

  map("R", function() self:refresh() end, "Refresh")
  map("q", "<cmd>close<cr>", "Close")
  map("<CR>", function() self:toggle() end, "Toggle / Expand directory")
  map("o", function() self:_open_file() end, "Open file")
end

--- Collect expanded node IDs before refresh, restore after
function Tree:refresh()
  local expanded = {}
  local function collect(node)
    if node.expanded then
      expanded[node.id] = true
    end
    if node.children then
      for _, child in ipairs(node.children) do
        collect(child)
      end
    end
  end
  collect(self.state.root)

  local new_root = self.provider:scan(self.root_path, 0)

  -- Restore expanded state on the new tree
  local function restore(node)
    if expanded[node.id] then
      node.expanded = true
      if node.children then
        for _, child in ipairs(node.children) do
          if child.type == "directory" then
            restore(child)
          end
        end
      end
    end
  end
  restore(new_root)

  self.state.root = new_root
  self:render()
end

--- Toggle directory expand/collapse at cursor
function Tree:toggle()
  local nodes = self:get_visible_nodes()
  if #nodes == 0 then return end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = nodes[idx]

  if not node or node.type == "file" then
    self:_open_file()
    return
  end

  -- Lazy load children if expanding for the first time
  if not node.expanded and node.type == "directory" and node.children and #node.children == 0 then
    local scanned = self.provider:scan(node.path, node.depth)
    node.children = scanned.children
  end

  node.expanded = not node.expanded
  self:render()
end

--- Open the file under cursor in the main editing area
function Tree:_open_file()
  local nodes = self:get_visible_nodes()
  if #nodes == 0 then return end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = nodes[idx]

  if not node or node.type ~= "file" then return end

  -- Switch to the window to the right (main editor)
  vim.cmd("wincmd l")
  vim.cmd("edit " .. vim.fn.fnameescape(node.path))
end

---@param opts table|nil
---@return bsi.Tree
function M.new(opts)
  return Tree.new(opts)
end

--- Setup commands and default keymaps
function M.setup()
  vim.api.nvim_create_user_command("BSITree", function(args)
    local root = args.args ~= "" and args.args or nil
    M.new({ root = root }):open()
  end, { nargs = "?", complete = "dir" })

  vim.keymap.set("n", "<leader>tt", function() M.new():open() end, { desc = "Open BSI Tree" })

  vim.keymap.set("n", "<leader>te", function()
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, bufnr)
    M.new({ bufnr = bufnr }):open()
  end, { desc = "Open BSI Tree (embedded)" })
end

return M
