-- lua/bsi/ui/tree.lua
-- BSI Tree: filesystem file tree with scan-based gitignore greying and async +N-M.
-- No porcelain status, directory AMD summaries, git-only mode, or Project watchers.

local M = {}

M.instances = {}

-- One-time namespace for all extmarks (cheaper than create_namespace on every render)
local ns_id = vim.api.nvim_create_namespace("bsitree")

-- Track last opened file path we synced trees to, to avoid redundant find_file+render
-- on every BufEnter (only pay when user actually switched main editing file)
M._last_synced_file = ""

-- "The one" main BSI tree instance for <leader>ee.
M.the_tree = nil

-- Tracked "opened buffer": the single main editing buffer the user is working with.
-- Used for current-file highlighting and find_file syncing.
M.opened_buffer = nil

-- Files staged for paste. Visual-mode `y` copies; `x` cuts. `paths` are normalized.
---@type { action: "copy"|"cut", paths: string[] }|nil
M.file_clip = nil

--- Default configuration for the tree
M.config = {
  -- When false, name-based heavy dirs (node_modules, vendor, …) and .git are hidden.
  -- Dotfiles (names starting with ".") are always included except .git when hidden.
  -- Toggle with 'h' inside the tree. Shown on open.
  show_ignored = true,
  -- Auto window width (columns) from the longest visible row, clamped here.
  width_min = 30,
  width_max = 100,
}

---@param lines string[]
---@return integer
function M.needed_width(lines)
  local n = 0
  for _, line in ipairs(lines or {}) do
    local w = vim.fn.strdisplaywidth(line)
    if w > n then
      n = w
    end
  end
  return n + 1
end

---@param needed integer
---@param min integer|nil
---@param max integer|nil
---@return integer
function M.clamped_width(needed, min, max)
  min = min or M.config.width_min or 30
  max = max or M.config.width_max or 100
  if min > max then
    min = max
  end
  needed = needed or 0
  if needed < min then
    return min
  end
  if needed > max then
    return max
  end
  return needed
end

local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local Provider = require("bsi.fs.provider")
local create_fs = require("bsi.fs.create")
local copy_fs = require("bsi.fs.copy")
local prune_fs = require("bsi.fs.prune")
local system = require("bsi.system")
local git_ignore = require("bsi.git.ignore")
local git_numstat = require("bsi.git.numstat")
local git_amd = require("bsi.git.amd")

--- Safely close a window, handling the "cannot close last window" (E444) case.
local function safe_close_win(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  local tab = vim.api.nvim_win_get_tabpage(winid)
  local tab_wins = vim.api.nvim_tabpage_list_wins(tab)
  if #tab_wins <= 1 then
    pcall(vim.cmd, "enew")
    return
  end
  pcall(vim.api.nvim_win_close, winid, true)
end

---@class bsi.Node
---@field id string
---@field name string
---@field path string
---@field type "file"|"directory"|"root"
---@field depth integer
---@field expanded boolean
---@field children bsi.Node[]|nil
---@field git_ignored boolean|nil
---@field git_numstat { added: integer, deleted: integer }|nil
---@field git_letter "A"|"M"|"D"|nil
---@field git_status_summary string|nil

---@class bsi.TreeState
---@field root bsi.Node

---@class bsi.Renderer
local Renderer = {}
Renderer.__index = Renderer

function Renderer.new()
  return setmetatable({}, Renderer)
end

--- Build buffer lines and highlight specs (no window required).
---@param nodes bsi.Node[]
---@return { lines: string[], highlights: table[] }
function Renderer:build(nodes)
  local lines = {}
  local highlights = {}
  local indent_cache = { ["0"] = "", ["1"] = " ", ["2"] = "  ", ["3"] = "   ", ["4"] = "    " }
  local current_file = M.get_opened_file()

  for i, node in ipairs(nodes) do
    local display_depth = node.depth - 1
    if display_depth < 0 then
      display_depth = 0
    end
    local indent = indent_cache[tostring(display_depth)] or string.rep(" ", display_depth)
    local arrow = "  "
    local icon = ""
    local icon_hl = nil
    local name_hl = nil
    local is_current = node.path == current_file

    if node.type == "root" or node.type == "directory" then
      if node.expanded then
        if node.children and #node.children == 0 then
          icon = ""
        else
          icon = ""
        end
        arrow = " "
      else
        icon = ""
        arrow = " "
      end
      name_hl = "Directory"
    else
      arrow = "  "
      if node._icon then
        icon = node._icon
        icon_hl = node._icon_hl
      elseif has_devicons then
        local ic, hl = devicons.get_icon(node.name, vim.fn.fnamemodify(node.name, ":e"), { default = true })
        icon = ic
        icon_hl = hl
      else
        icon = ""
      end
    end

    local numstat_part = ""
    local letter_part = ""
    if not node.git_ignored then
      if node.type == "file" then
        if node.git_numstat then
          numstat_part = git_numstat.format(node.git_numstat.added, node.git_numstat.deleted)
        end
        if node.git_letter then
          letter_part = " " .. node.git_letter
        end
      elseif node.git_status_summary and node.git_status_summary ~= "" then
        letter_part = " " .. node.git_status_summary
      end
    end
    local detail = numstat_part .. letter_part

    local line_content = table.concat({ indent, arrow, icon, " ", node.name, detail })
    table.insert(lines, line_content)

    if is_current then
      table.insert(highlights, { hl = "BSITreeCurrentFile", line = i - 1, col_start = 0, col_end = -1 })
    end

    local current_col = #indent
    local arrow_start = current_col
    local arrow_end = arrow_start + #arrow
    local icon_start = arrow_end
    local icon_end = icon_start + #icon
    local name_start = icon_end + 1
    local name_end = name_start + #node.name

    if node.git_ignored then
      table.insert(highlights, {
        hl = "BSITreeGitIgnored",
        line = i - 1,
        col_start = arrow_start,
        col_end = name_end,
      })
    else
      if icon_hl then
        table.insert(highlights, { hl = icon_hl, line = i - 1, col_start = icon_start, col_end = icon_end })
      end
      if name_hl then
        table.insert(highlights, {
          hl = name_hl,
          line = i - 1,
          col_start = name_start,
          col_end = name_end,
        })
      end
      if numstat_part ~= "" then
        local detail_start = name_end
        local first = numstat_part:sub(2, 2)
        if first == "+" then
          local hyphen = numstat_part:find("-", 3, true) or (#numstat_part + 1)
          local split = detail_start + hyphen - 1
          table.insert(highlights, {
            hl = "BSITreeGitAdded",
            line = i - 1,
            col_start = detail_start + 1,
            col_end = split,
          })
          if hyphen <= #numstat_part then
            table.insert(highlights, {
              hl = "BSITreeGitDeleted",
              line = i - 1,
              col_start = split,
              col_end = detail_start + #numstat_part,
            })
          end
        elseif first == "-" then
          table.insert(highlights, {
            hl = "BSITreeGitDeleted",
            line = i - 1,
            col_start = detail_start + 1,
            col_end = detail_start + #numstat_part,
          })
        end
      end
      if letter_part ~= "" then
        local letter_hl = {
          A = "BSITreeGitAdded",
          M = "BSITreeGitModified",
          D = "BSITreeGitDeleted",
        }
        local letters = letter_part:sub(2)
        local col = name_end + #numstat_part + 1
        for j = 1, #letters do
          local ch = letters:sub(j, j)
          local hl = letter_hl[ch]
          if hl then
            table.insert(highlights, {
              hl = hl,
              line = i - 1,
              col_start = col + j - 1,
              col_end = col + j,
            })
          end
        end
      end
    end

    local clip = M.file_clip
    if clip and clip.paths and node.path and node.type ~= "root" then
      local node_path = node.path
      local normalized = vim.fs.normalize(node_path):gsub("/$", "")
      local matched = false
      for _, clip_path in ipairs(clip.paths) do
        if node_path == clip_path or normalized == clip_path then
          matched = true
          break
        end
      end
      if matched then
        table.insert(highlights, {
          hl = clip.action == "cut" and "BSITreeCut" or "BSITreeCopied",
          line = i - 1,
          col_start = name_start,
          col_end = name_end,
        })
      end
    end
  end

  return { lines = lines, highlights = highlights }
end

--- Renders the provided nodes into the buffer with indentation, icons, and highlights
---@param bufnr integer
---@param nodes bsi.Node[]
---@param winid integer|nil
function Renderer:render(bufnr, nodes, winid)
  local built = self:build(nodes)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, built.lines)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  for _, hl in ipairs(built.highlights) do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl.hl, hl.line, hl.col_start, hl.col_end)
  end
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "Tree"

  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_option_value("number", false, { win = winid })
    vim.api.nvim_set_option_value("relativenumber", false, { win = winid })
    pcall(vim.api.nvim_set_option_value, "wrap", false, { win = winid })
  end
  return built
end

---@class bsi.Tree
local Tree = {}
Tree.__index = Tree

--- Creates a new Tree instance and performs initial scan
---@param opts table|nil { root, expand_all, bufnr, winid, show_ignored }
function Tree.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Tree)
  self.provider = Provider.new()
  self.renderer = Renderer.new()
  local raw_root = opts.root or vim.fn.getcwd()
  self.root_path = vim.fn.resolve(vim.fn.fnamemodify(raw_root, ":p")):gsub("/$", "")
  self.opts = opts

  if opts.show_ignored ~= nil then
    self.show_ignored = opts.show_ignored
  else
    self.show_ignored = M.config.show_ignored
  end

  local initial_max_depth = opts.expand_all and nil or 1
  self._scan_opts = {
    expand_all = opts.expand_all,
    show_ignored = self.show_ignored,
    max_depth = initial_max_depth,
  }

  self._ignore = opts.ignore or git_ignore
  self._numstat = opts.numstat or git_numstat
  self._amd = opts.amd or git_amd
  self._git_gen = 0
  self._width_manual = false

  local root = self.provider:scan(self.root_path, 0, self._scan_opts)
  self.state = {
    root = root or {
      id = self.root_path,
      name = vim.fn.fnamemodify(self.root_path, ":t"),
      path = self.root_path,
      type = "root",
      depth = 0,
      expanded = true,
      children = {},
    },
  }
  self._visible_dirty = true
  self.bufnr = opts.bufnr
  self.winid = opts.winid
  self:_annotate()
  self:_fetch_git()
  return self
end

function Tree:_annotate()
  if self.state and self.state.root and self._ignore then
    self._ignore.annotate(self.state.root)
  end
end

function Tree:_stamp_numstat(node, map)
  if node.type == "file" then
    if node.git_ignored then
      node.git_numstat = nil
    else
      node.git_numstat = map[node.path]
    end
  end
  for _, child in ipairs(node.children or {}) do
    self:_stamp_numstat(child, map)
  end
end

function Tree:_fetch_git()
  self._git_gen = (self._git_gen or 0) + 1
  local gen = self._git_gen
  self:_fetch_numstat(gen)
  self:_fetch_amd(gen)
end

function Tree:_fetch_numstat(gen)
  gen = gen or self._git_gen
  local fetch = self._numstat and self._numstat.fetch_async
  if not fetch then
    return
  end
  fetch(self.root_path, function(map)
    if gen ~= self._git_gen then
      return
    end
    if type(map) ~= "table" then
      return
    end
    self:_stamp_numstat(self.state.root, map)
    self._visible_dirty = true
    if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
      self:render()
    end
  end)
end

function Tree:_fetch_amd(gen)
  gen = gen or self._git_gen
  local fetch = self._amd and self._amd.fetch_async
  if not fetch then
    return
  end
  fetch(self.root_path, function(map)
    if gen ~= self._git_gen then
      return
    end
    if type(map) ~= "table" then
      return
    end
    self._amd_map = map
    self._amd.stamp(self.state.root, map)
    self._visible_dirty = true
    if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
      self:render()
    end
  end)
end

local function merge_chain_name(display_name, old_path, scanned_name)
  local last = vim.fn.fnamemodify(old_path, ":t")
  if last ~= "" and #display_name >= #last and display_name:sub(-#last) == last then
    return display_name:sub(1, #display_name - #last) .. scanned_name
  end
  if display_name == scanned_name or scanned_name:sub(1, #display_name + 1) == display_name .. "/" then
    return scanned_name
  end
  return display_name .. "/" .. scanned_name
end

function Tree:_load_directory(node)
  local guard = {}
  while true do
    if guard[node.path] then
      break
    end
    guard[node.path] = true
    local scanned = self.provider:scan(node.path, node.depth, {
      show_ignored = self.show_ignored,
    })
    if not scanned then
      node.children = node.children or {}
      break
    end
    if scanned.path ~= node.path then
      node.name = merge_chain_name(node.name, node.path, scanned.name)
      node.path = scanned.path
      node.id = scanned.id
    end
    node.children = scanned.children or {}
    node._unpopulated = scanned._unpopulated and true or false

    local dirs = {}
    local nfiles = 0
    for _, c in ipairs(node.children) do
      if c.type == "directory" then
        dirs[#dirs + 1] = c
      else
        nfiles = nfiles + 1
      end
    end
    -- Stop on the last directory that actually contains files.
    if nfiles > 0 then
      break
    end
    if #dirs == 1 then
      local child = dirs[1]
      node.name = node.name .. "/" .. child.name
      node.path = child.path
      node.id = child.id
      node.children = child.children or {}
      node._unpopulated = child._unpopulated and true or false
    else
      break
    end
  end
  node._unpopulated = false
  self:_annotate()
  if self._amd_map and self._amd then
    self._amd.stamp(self.state.root, self._amd_map)
  end
end

---@return string
function Tree:get_root_path()
  return vim.fn.fnamemodify(self.root_path, ":~")
end

---@return bsi.Node[]
function Tree:get_visible_nodes()
  if self._visible_nodes and not self._visible_dirty then
    return self._visible_nodes
  end
  local nodes = {}
  local function walk(node)
    if node.type ~= "root" then
      table.insert(nodes, node)
    end
    if (node.type == "directory" or node.type == "root") and node.expanded and node.children then
      for _, child in ipairs(node.children) do
        walk(child)
      end
    end
  end
  walk(self.state.root)
  self._visible_nodes = nodes
  self._visible_dirty = false
  return nodes
end

function Tree:render()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    return
  end

  local now = (vim.uv and vim.uv.now and vim.uv.now()) or 0
  if not self._visible_dirty and self._last_render_ms and (now - self._last_render_ms) < 60 then
    self:_apply_width()
    return
  end
  self._last_render_ms = now

  self.visible_nodes = self:get_visible_nodes()
  local built = self.renderer:render(self.bufnr, self.visible_nodes, self.winid)
  self._last_lines = built and built.lines or {}
  self:_apply_width()
  -- Layout may not have settled until the next tick (split/expand).
  vim.schedule(function()
    self:_apply_width()
  end)
end

function Tree:_width_bounds()
  local min = M.config.width_min or 30
  local max = M.config.width_max or 100
  if min > max then
    min = max
  end
  return min, max
end

function Tree:_apply_width()
  if self._width_manual then
    return
  end
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    return
  end
  local min, max = self:_width_bounds()
  local needed = M.needed_width(self._last_lines or {})
  local w = M.clamped_width(needed, min, max)
  if vim.api.nvim_win_get_width(self.winid) ~= w then
    vim.api.nvim_win_set_width(self.winid, w)
  end
end

function Tree:nudge_width(delta)
  self._width_manual = true
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    return
  end
  local min = select(1, self:_width_bounds())
  local cap = math.max(min, (vim.o.columns or 120) - 1)
  local cur = vim.api.nvim_win_get_width(self.winid)
  local w = cur + (delta or 0)
  if w < min then
    w = min
  end
  if w > cap then
    w = cap
  end
  if cur ~= w then
    vim.api.nvim_win_set_width(self.winid, w)
  end
end

function Tree:expand_width()
  self:nudge_width(3)
end

function Tree:restore_width()
  self:nudge_width(-3)
end

function Tree:_update_winbar()
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    return
  end
  local title = self:get_root_path()
  if self._refreshing then
    title = title .. " (refreshing...)"
  end
  vim.api.nvim_set_hl(0, "BSITreeTitle", { fg = "#3EFFDC", bold = true })
  vim.wo[self.winid].winbar = "%#BSITreeTitle# " .. title
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

  -- Scratch / non-file buffer: never a valid :edit target (Telescope, etc.)
  vim.bo[self.bufnr].buftype = "nofile"
  vim.bo[self.bufnr].bufhidden = "wipe"
  vim.bo[self.bufnr].swapfile = false
  vim.bo[self.bufnr].modifiable = false

  M.instances[self.bufnr] = self
  pcall(vim.api.nvim_buf_set_name, self.bufnr, "BSITree")

  self._width_manual = false

  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_set_option_value("cursorline", true, { win = self.winid })
    vim.api.nvim_set_option_value("winhighlight", "CursorLine:BSITreeCursorLine", { win = self.winid })
    -- Forbid replacing the tree buffer in this window (Telescope/edit must use another win)
    pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = self.winid })
    pcall(vim.api.nvim_set_option_value, "winfixwidth", true, { win = self.winid })
  end

  self:render()

  local opened = M.get_opened_file()
  if opened ~= "" then
    self:find_file(opened)
  end

  self:_update_winbar()

  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = self.bufnr, silent = true, desc = "Tree: " .. desc })
  end

  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = self.bufnr,
    callback = function()
      M.instances[self.bufnr] = nil
      if M.the_tree and M.the_tree.bufnr == self.bufnr then
        M.the_tree = nil
      end
    end,
  })

  map(">", function()
    self:nudge_width(3)
  end, "Widen tree by 3 columns")
  map("<", function()
    self:nudge_width(-3)
  end, "Narrow tree by 3 columns")
  map("R", function()
    self:refresh()
  end, "Refresh")
  map("h", function()
    self:toggle_show_ignored()
  end, "Toggle ignored dirs (node_modules, vendor, .git, …)")
  map("q", function()
    safe_close_win(vim.api.nvim_get_current_win())
  end, "Close")
  map("<CR>", function()
    self:toggle()
  end, "Toggle / Expand directory")
  map("o", function()
    self:_open_system()
  end, "Open with system default app")
  map("d", function()
    self:_delete_node()
  end, "Delete file or directory")
  map("D", function()
    self:_diff_file()
  end, "Diff file")
  map("a", function()
    self:_add_file()
  end, "Add new file")
  map("r", function()
    self:rename_or_move()
  end, "Rename / Move")
  map("u", function()
    self:rename_or_move()
  end, "Rename / Move")
  map("y", function()
    self:_stage_cursor("copy")
  end, "Copy file")
  map("Y", function()
    self:_yank(true)
  end, "Yank relative path")
  map("c", function()
    self:copy_contents(self:_cursor_node())
  end, "Copy file contents")
  map("x", function()
    self:_stage_cursor("cut")
  end, "Cut file for paste")
  map("p", function()
    self:_paste_cursor()
  end, "Paste files")
  vim.keymap.set("x", "y", function()
    self:_copy_visual()
  end, { buffer = self.bufnr, silent = true, desc = "Tree: Copy selection for paste" })
  vim.keymap.set("x", "c", function()
    self:_copy_visual_contents()
  end, { buffer = self.bufnr, silent = true, desc = "Tree: Copy selection contents" })
  map("<LeftMouse>", "<LeftMouse>", "Select node")
  map("<2-LeftMouse>", function()
    self:toggle()
  end, "Open file / Toggle directory")

  map("gg", function()
    if self.winid and vim.api.nvim_win_is_valid(self.winid) then
      pcall(vim.api.nvim_win_set_cursor, self.winid, { 1, 0 })
    end
  end, "Go to top of tree")

  map("G", function()
    local nodes = self.visible_nodes or self:get_visible_nodes() or {}
    if self.winid and vim.api.nvim_win_is_valid(self.winid) and #nodes > 0 then
      pcall(vim.api.nvim_win_set_cursor, self.winid, { #nodes, 0 })
    end
  end, "Go to bottom of tree")
end

--- Re-scan filesystem, preserving expansion state
function Tree:refresh()
  local expanded = {}
  local function mark_expanded(path)
    if path and path ~= "" then
      expanded[path] = true
    end
  end
  local function collect(node)
    if node.expanded then
      mark_expanded(node.id)
      mark_expanded(node.path)
      -- Collapsed "foo/bar" lives at bar's path; parent foo must also reload.
      if node.name and node.name:find("/") then
        local p = node.path
        for _ in node.name:gmatch("/") do
          p = vim.fn.fnamemodify(p, ":h"):gsub("/$", "")
          mark_expanded(p)
        end
      end
    end
    if node.children then
      for _, child in ipairs(node.children) do
        collect(child)
      end
    end
  end
  collect(self.state.root)
  expanded[self.root_path] = true

  self._refreshing = true
  self:_update_winbar()

  -- Same bound as first open; expanded dirs are filled by populate_expanded.
  local scan_opts = {
    expand_all = self.opts and self.opts.expand_all,
    show_ignored = self.show_ignored,
    max_depth = (self.opts and self.opts.expand_all) and nil or 1,
  }
  local new_root = self.provider:scan(self.root_path, 0, scan_opts)
  new_root = new_root
    or {
      id = self.root_path,
      name = vim.fn.fnamemodify(self.root_path, ":t"),
      path = self.root_path,
      type = "root",
      depth = 0,
      expanded = true,
      children = {},
    }

  local function should_expand(node)
    return expanded[node.id] or expanded[node.path] or (self.opts and self.opts.expand_all)
  end

  local function restore(node)
    if should_expand(node) then
      node.expanded = true
    end
    if node.children then
      for _, child in ipairs(node.children) do
        restore(child)
      end
    end
  end
  restore(new_root)
  new_root.expanded = true

  local scan_one = {
    show_ignored = self.show_ignored,
  }

  -- Reload expanded stubs. If scan collapses foo → foo/bar, follow the new path.
  local function populate_expanded(node)
    if (node.type == "directory" or node.type == "root") and node.expanded then
      local guard = {}
      while node._unpopulated or node.children == nil do
        if guard[node.path] then
          break
        end
        guard[node.path] = true
        local sc = self.provider:scan(node.path, node.depth, scan_one)
        if not sc then
          node._unpopulated = false
          node.children = node.children or {}
          break
        end
        -- Scan may collapse foo → foo/bar (new path). Don't rename when
        -- re-scanning an already-collapsed node (path unchanged, name "bar").
        if sc.path ~= node.path then
          node.name = sc.name
          node.path = sc.path
          node.id = sc.id
        end
        node.children = sc.children or {}
        node._unpopulated = sc._unpopulated and true or false
      end
      if node.children then
        for _, child in ipairs(node.children) do
          if should_expand(child) then
            child.expanded = true
          end
          populate_expanded(child)
        end
      end
    elseif node.children then
      for _, child in ipairs(node.children) do
        populate_expanded(child)
      end
    end
  end
  populate_expanded(new_root)

  self.state.root = new_root
  self:_annotate()
  self:_fetch_git()
  self._width_manual = false
  self._visible_dirty = true
  self._refreshing = false

  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    self:render()
  end
  self:_update_winbar()
end

function Tree:toggle_show_ignored()
  self.show_ignored = not (self.show_ignored or false)
  self:refresh()
end

function Tree:toggle()
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node or node.type == "file" then
    self:_open_file()
    return
  end
  if not node.expanded and node.type == "directory" then
    local needs_load = (node.children and #node.children == 0) or node._unpopulated
    if needs_load then
      self:_load_directory(node)
    end
  end
  node.expanded = not node.expanded
  self._width_manual = false
  self._visible_dirty = true
  self:render()
end

---@param win integer
---@return boolean
function Tree:_is_editor_win(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if win == self.winid then
    return false
  end
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative ~= "" then
    return false
  end
  local ok_fix, fix = pcall(vim.api.nvim_get_option_value, "winfixbuf", { win = win })
  if ok_fix and fix then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "Tree" then
    return false
  end
  return true
end

---@return integer|nil
function Tree:_find_editor_win()
  local tab = vim.api.nvim_get_current_tabpage()
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    tab = vim.api.nvim_win_get_tabpage(self.winid)
  end
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  local fallback
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if self:_is_editor_win(win) then
      if win == prev then
        return win
      end
      if not fallback then
        fallback = win
      end
    end
  end
  return fallback
end

--- Open `path` in a normal editor window. Never replaces the tree buffer.
---@param path string
function Tree:_edit_in_editor(path)
  if not path or path == "" then
    return
  end
  local win = self:_find_editor_win()
  if not win then
    if self.winid and vim.api.nvim_win_is_valid(self.winid) then
      vim.api.nvim_set_current_win(self.winid)
    end
    vim.cmd("vsplit")
    win = vim.api.nvim_get_current_win()
    -- vsplit copies window-local options; the new editor must be allowed to :edit.
    pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
    pcall(vim.api.nvim_set_option_value, "winfixwidth", false, { win = win })
  else
    vim.api.nvim_set_current_win(win)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

function Tree:_open_file()
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node or node.type ~= "file" then
    return
  end
  self:_edit_in_editor(node.path)
end

function Tree:_open_system()
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node then
    return
  end

  system.open_url(node.path)
end

function Tree:_diff_file()
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node or node.type ~= "file" then
    return
  end
  vim.cmd("DiffviewOpen -- " .. vim.fn.fnameescape(node.path))
end

function Tree:_delete_node()
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node or node.type == "root" then
    vim.notify("Cannot delete the root", vim.log.levels.WARN)
    return
  end

  local path = node.path
  local is_dir = node.type == "directory"
  local label = is_dir and "directory" or "file"

  local choice = vim.fn.confirm(
    "Delete " .. label .. " " .. vim.fn.fnamemodify(path, ":t") .. "?",
    "&Yes\n&No",
    2
  )
  if choice ~= 1 then
    return
  end

  local flags = is_dir and "rf" or ""
  local deleted = vim.fn.delete(path, flags)

  if deleted == 0 then
    vim.notify("Deleted " .. label .. ": " .. path, vim.log.levels.INFO)
    if M.opened_buffer and vim.api.nvim_buf_get_name(M.opened_buffer) == path then
      M.opened_buffer = nil
    end
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
    prune_fs(self.root_path, vim.fn.fnamemodify(path, ":h"))
    self:refresh()
  else
    vim.notify("Failed to delete " .. label .. ": " .. path, vim.log.levels.ERROR)
  end
end

local function normalize_path(p)
  return vim.fs.normalize(p or ""):gsub("/$", "")
end

--- Point loaded buffers that lived under `src` at the moved path.
---@param src string
---@param dst string
local function retarget_buffers(src, dst)
  src = normalize_path(src)
  dst = normalize_path(dst)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= "" then
        name = normalize_path(name)
        local new_name
        if name == src then
          new_name = dst
        elseif name:sub(1, #src + 1) == src .. "/" then
          new_name = dst .. name:sub(#src + 1)
        end
        if new_name then
          pcall(vim.api.nvim_buf_set_name, bufnr, new_name)
        end
      end
    end
  end
end

--- A free sibling path: `note.txt` -> `note-copy.txt`, then `note-copy2.txt`.
---@param path string
---@return string
local function unique_paste_path(path)
  path = normalize_path(path)
  if not (vim.uv or vim.loop).fs_lstat(path) then
    return path
  end
  local dir = vim.fn.fnamemodify(path, ":h")
  local name = vim.fn.fnamemodify(path, ":t")
  local stem, ext = name, ""
  if not (name:sub(1, 1) == "." and not name:sub(2):find(".", 1, true)) then
    local s, e = name:match("^(.*)(%.[^.]+)$")
    if s and s ~= "" then
      stem, ext = s, e
    end
  end
  local n = 1
  while true do
    local suffix = n == 1 and "-copy" or ("-copy" .. n)
    local candidate = dir .. "/" .. stem .. suffix .. ext
    if not (vim.uv or vim.loop).fs_lstat(candidate) then
      return candidate
    end
    n = n + 1
    if n > 1000 then
      return candidate
    end
  end
end

function Tree:_redraw_clip()
  self._visible_dirty = true
  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    self:render()
  end
end

---@return bsi.Node|nil
function Tree:_cursor_node()
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return nil
  end
  local win = 0
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    win = self.winid
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return self.visible_nodes[cursor[1]]
end

---@param node bsi.Node|nil
---@return string|nil
function Tree:_paste_dir(node)
  if not node or not node.path then
    return nil
  end
  if node.type == "directory" or node.type == "root" then
    return normalize_path(node.path)
  end
  return normalize_path(vim.fn.fnamemodify(node.path, ":h"))
end

---@param a string[]
---@param b string[]
---@return boolean
local function same_paths(a, b)
  if #a ~= #b then
    return false
  end
  local sa, sb = vim.deepcopy(a), vim.deepcopy(b)
  table.sort(sa)
  table.sort(sb)
  for i = 1, #sa do
    if sa[i] ~= sb[i] then
      return false
    end
  end
  return true
end

--- Drop a path that sits inside another staged path. Keep selection order otherwise.
---@param paths string[]
---@return string[]
local function prune_nested(paths)
  local kept = {}
  for _, path in ipairs(paths) do
    local skip = false
    local filtered = {}
    for _, prev in ipairs(kept) do
      if prev == path or (copy_fs.contains(prev, path) and prev ~= path) then
        skip = true
        filtered[#filtered + 1] = prev
      elseif copy_fs.contains(path, prev) and path ~= prev then
        -- prev is inside path; the parent replaces it
      else
        filtered[#filtered + 1] = prev
      end
    end
    kept = filtered
    if not skip then
      kept[#kept + 1] = path
    end
  end
  return kept
end

--- Stage nodes for paste. The same action and the same paths clear the stage.
--- A single node or a list of nodes is accepted. The root is skipped.
---@param node_or_nodes bsi.Node|bsi.Node[]|nil
---@param action "copy"|"cut"
function Tree:stage_clipboard(node_or_nodes, action)
  if action ~= "copy" and action ~= "cut" then
    return
  end
  local nodes = node_or_nodes
  if nodes and nodes.path then
    nodes = { nodes }
  end
  if type(nodes) ~= "table" then
    return
  end

  local paths = {}
  local saw = false
  for _, node in ipairs(nodes) do
    saw = true
    if node and node.type ~= "root" and node.path then
      paths[#paths + 1] = normalize_path(node.path)
    end
  end
  if not saw then
    return
  end
  if #paths == 0 then
    vim.notify("Cannot copy or cut the root", vim.log.levels.WARN)
    return
  end
  paths = prune_nested(paths)

  local clip = M.file_clip
  if clip and clip.action == action and clip.paths and same_paths(clip.paths, paths) then
    M.file_clip = nil
    vim.notify("Cleared clipboard", vim.log.levels.INFO)
  else
    M.file_clip = { action = action, paths = paths }
    local verb = action == "cut" and "Cut " or "Yanked "
    if #paths == 1 then
      vim.notify(verb .. paths[1], vim.log.levels.INFO)
    else
      vim.notify(verb .. #paths .. " paths", vim.log.levels.INFO)
    end
  end
  self:_redraw_clip()
end

---@param action "copy"|"cut"
function Tree:_stage_cursor(action)
  self:stage_clipboard(self:_cursor_node(), action)
end

--- Copy the visible rows from `line1` through `line2` (inclusive, 1-based).
---@param line1 integer
---@param line2 integer
---@param action "copy"|"cut"|nil
function Tree:copy_lines(line1, line2, action)
  if not self.visible_nodes then
    return
  end
  if line1 > line2 then
    line1, line2 = line2, line1
  end
  local nodes = {}
  for i = line1, line2 do
    local node = self.visible_nodes[i]
    if node then
      nodes[#nodes + 1] = node
    end
  end
  self:stage_clipboard(nodes, action or "copy")
end

function Tree:_visual_line_range()
  local line1 = vim.fn.line("v")
  local line2 = vim.fn.line(".")
  if line1 < 1 or line2 < 1 then
    line1 = vim.fn.line("'<")
    line2 = vim.fn.line("'>")
  end
  return line1, line2
end

function Tree:_copy_visual()
  local line1, line2 = self:_visual_line_range()
  self:copy_lines(line1, line2, "copy")
end

function Tree:_nodes_in_range(line1, line2)
  if not self.visible_nodes then
    return {}
  end
  if line1 > line2 then
    line1, line2 = line2, line1
  end
  local nodes = {}
  for i = line1, line2 do
    local node = self.visible_nodes[i]
    if node then
      nodes[#nodes + 1] = node
    end
  end
  return nodes
end

function Tree:_copy_visual_contents()
  local line1, line2 = self:_visual_line_range()
  self:copy_contents(self:_nodes_in_range(line1, line2))
end

---@param action "copy"|"cut"
---@param src string
---@param dest string
---@param cb fun(ok: boolean)
function Tree:_commit_one(action, src, dest, cb)
  dest = normalize_path(dest)
  src = normalize_path(src)
  local lst = (vim.uv or vim.loop).fs_lstat(src)
  if not lst then
    vim.notify("Source is gone: " .. src, vim.log.levels.ERROR)
    cb(true)
    return
  end

  if lst.type == "directory" and src ~= dest and copy_fs.contains(src, dest) then
    vim.notify("Cannot paste a directory into itself", vim.log.levels.WARN)
    cb(false)
    return
  end

  if action == "cut" and src == dest then
    vim.notify("Already there", vim.log.levels.INFO)
    cb(true)
    return
  end

  local parent = normalize_path(vim.fn.fnamemodify(dest, ":h"))
  if parent ~= "" and parent ~= dest and vim.fn.isdirectory(parent) == 0 then
    if vim.fn.mkdir(parent, "p") == 0 then
      vim.notify("Failed to create " .. parent, vim.log.levels.ERROR)
      cb(false)
      return
    end
  end

  if src == dest or (vim.uv or vim.loop).fs_lstat(dest) then
    vim.ui.input({
      prompt = "Paste as: ",
      default = unique_paste_path(dest),
      completion = "file",
    }, function(new_dest)
      if not new_dest or vim.trim(new_dest) == "" then
        cb(false)
        return
      end
      self:_commit_one(action, src, new_dest, cb)
    end)
    return
  end

  if action == "cut" then
    local moved, err = self:_move_path(src, dest)
    if not moved then
      vim.notify("Failed to move: " .. (err or dest), vim.log.levels.ERROR)
      cb(false)
      return
    end
    retarget_buffers(src, dest)
    prune_fs(self.root_path, vim.fn.fnamemodify(src, ":h"))
    vim.notify("Moved " .. src .. " → " .. dest, vim.log.levels.INFO)
    cb(true)
    return
  end

  local result = copy_fs(src, dest)
  if not result.ok then
    vim.notify("Failed to copy: " .. (result.err or dest), vim.log.levels.ERROR)
    cb(false)
    return
  end
  vim.notify("Copied " .. src .. " → " .. dest, vim.log.levels.INFO)
  cb(true)
end

--- Paste the staged files into `node` (or into its parent when `node` is a file).
---@param node bsi.Node|nil
function Tree:paste_clipboard(node)
  local clip = M.file_clip
  if not clip or not clip.paths or #clip.paths == 0 then
    vim.notify("Nothing to paste", vim.log.levels.WARN)
    return
  end
  local dest_dir = self:_paste_dir(node)
  if not dest_dir then
    return
  end

  local paths = {}
  for i, path in ipairs(clip.paths) do
    paths[i] = path
  end
  local action = clip.action
  local last_dest

  local function step(i)
    if i > #paths then
      M.file_clip = nil
      self:refresh()
      if last_dest and self.winid and vim.api.nvim_win_is_valid(self.winid) then
        self:find_file(last_dest)
      end
      return
    end
    local src = paths[i]
    local base = vim.fn.fnamemodify(src, ":t")
    if base == "" then
      step(i + 1)
      return
    end
    self:_commit_one(action, src, dest_dir .. "/" .. base, function(ok)
      if not ok then
        local rest = {}
        for j = i, #paths do
          rest[#rest + 1] = paths[j]
        end
        M.file_clip = { action = action, paths = rest }
        self:_redraw_clip()
        return
      end
      last_dest = dest_dir .. "/" .. base
      step(i + 1)
    end)
  end

  step(1)
end

function Tree:_paste_cursor()
  self:paste_clipboard(self:_cursor_node())
end

local CAT_MAX = 512 * 1024

---@param path string
---@return string|nil
---@return string|nil err
local function read_cat_file(path)
  local uv = vim.uv or vim.loop
  local lst = uv.fs_stat(path)
  if not lst or lst.type ~= "file" then
    return nil, "missing"
  end
  if lst.size == 0 then
    return ""
  end
  local fd, open_err = uv.fs_open(path, "r", 438)
  if not fd then
    return nil, open_err or "unreadable"
  end
  local n = math.min(lst.size, CAT_MAX)
  local data = uv.fs_read(fd, n, 0) or ""
  uv.fs_close(fd)
  if data:find("\0", 1, true) then
    return "[binary " .. lst.size .. " bytes]"
  end
  if lst.size > CAT_MAX then
    if data:sub(-1) ~= "\n" then
      data = data .. "\n"
    end
    data = data .. "[truncated]\n"
  end
  return data
end

---@param dir string
---@return { name: string, path: string }[]|nil
local function list_dir_files(dir)
  local uv = vim.uv or vim.loop
  local handle = uv.fs_scandir(dir)
  if not handle then
    return nil
  end
  local files = {}
  while true do
    local name, etype = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local full = dir .. "/" .. name
    local include = etype == "file"
    if etype == "link" or not etype then
      local st = uv.fs_stat(full)
      include = st ~= nil and st.type == "file"
    end
    if include then
      files[#files + 1] = { name = name, path = full }
    end
  end
  table.sort(files, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return files
end

---@param data string
---@return string[]
local function body_lines(data)
  if data == "" then
    return { "" }
  end
  local lines = vim.split(data, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  if #lines == 0 then
    return { "" }
  end
  return lines
end

--- Text of one file, or of the files directly inside a directory.
--- Subdirectories are not included. A directory listing labels each file.
---@param node bsi.Node|nil
---@return string|nil
---@return string|nil err
function Tree:cat_text(node)
  if not node or not node.path then
    return nil, "missing"
  end
  local path = normalize_path(node.path)
  local uv = vim.uv or vim.loop
  local lst = uv.fs_stat(path)
  if not lst then
    return nil, "missing"
  end
  local as_dir = lst.type == "directory" or node.type == "directory" or node.type == "root"
  if not as_dir then
    return read_cat_file(path)
  end

  local files = list_dir_files(path)
  if not files then
    return nil, "unreadable"
  end
  if #files == 0 then
    return nil, "empty"
  end
  local lines = {}
  for i, file in ipairs(files) do
    if i > 1 then
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "==> " .. file.name .. " <=="
    local body, err = read_cat_file(file.path)
    if not body then
      lines[#lines + 1] = "[" .. (err or "unreadable") .. "]"
    else
      for _, line in ipairs(body_lines(body)) do
        lines[#lines + 1] = line
      end
    end
  end
  return table.concat(lines, "\n")
end

--- Put file contents on the paste registers. One file is the raw text.
--- A directory, or several nodes, is the same labeled listing `cat_text` builds.
---@param node_or_nodes bsi.Node|bsi.Node[]|nil
---@return string|nil
function Tree:copy_contents(node_or_nodes)
  local nodes = node_or_nodes
  if nodes and nodes.path then
    nodes = { nodes }
  end
  if type(nodes) ~= "table" or #nodes == 0 then
    vim.notify("Nothing to copy", vim.log.levels.WARN)
    return nil
  end

  local chunks = {}
  local empty = false
  for _, node in ipairs(nodes) do
    if node and node.type ~= "root" then
      local text, err = self:cat_text(node)
      if text then
        chunks[#chunks + 1] = text
      elseif err == "empty" then
        empty = true
      end
    end
  end
  if #chunks == 0 then
    if empty then
      vim.notify("No files to copy", vim.log.levels.WARN)
    else
      vim.notify("Nothing to copy", vim.log.levels.WARN)
    end
    return nil
  end

  local text = table.concat(chunks, "\n\n")
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify("Copied contents", vim.log.levels.INFO)
  return text
end

---@param full boolean
function Tree:_yank(full)
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node then
    return
  end
  local text = full and (node.path:sub(#self.root_path + 2)) or node.name
  if text == "" then
    text = "."
  end
  -- Both registers now. A deferred "+" write loses to clipboard=unnamedplus
  -- and a paste can still see the previous clipboard value.
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify("Yanked " .. text, vim.log.levels.INFO)
end

function Tree:_add_file()
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node then
    return
  end

  local target_dir = (node.type == "directory" or node.type == "root") and node.path
    or vim.fn.fnamemodify(node.path, ":h")

  vim.ui.input({
    prompt = "New file: ",
    default = create_fs.default_path(self.root_path, target_dir),
    completion = "file",
  }, function(input)
    local result = create_fs(self.root_path, input)
    if result.kind == "empty" then
      return
    end
    if result.kind == "exists" then
      vim.notify("Already exists: " .. (result.path or input), vim.log.levels.WARN)
      return
    end
    if not result.ok then
      vim.notify("Failed to create: " .. (result.err or result.path or "unknown"), vim.log.levels.ERROR)
      return
    end

    self:refresh()
    if result.path then
      self:find_file(result.path)
    end

    if result.kind == "file" and result.path then
      vim.schedule(function()
        self:_edit_in_editor(result.path)
      end)
    end
  end)
end

---@param src string
---@param dst string
---@return boolean success
---@return string|nil error
function Tree:_move_path(src, dst)
  local stat = vim.loop.fs_stat(src)
  if not stat then
    return false, "Source does not exist"
  end

  local ok = vim.loop.fs_rename(src, dst)
  if ok then
    return true
  end

  vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")

  if stat.type == "file" then
    local content = vim.fn.readfile(src, "b")
    vim.fn.writefile(content, dst, "b")
    vim.loop.fs_unlink(src)
    return true
  end

  if stat.type == "directory" then
    vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
    if not vim.loop.fs_stat(dst) then
      local mkdir_ok = vim.loop.fs_mkdir(dst, 493)
      if not mkdir_ok then
        return false, "Failed to create destination directory"
      end
    end

    local handle = vim.loop.fs_scandir(src)
    if handle then
      while true do
        local name = vim.loop.fs_scandir_next(handle)
        if not name then
          break
        end
        local success, move_err = self:_move_path(src .. "/" .. name, dst .. "/" .. name)
        if not success then
          return false, move_err
        end
      end
    end
    vim.loop.fs_rmdir(src)
    return true
  end

  return false, "Unsupported file type: " .. stat.type
end

function Tree:rename_or_move()
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node or node.type == "root" then
    vim.notify("Cannot rename/move the root", vim.log.levels.WARN)
    return
  end

  local current = node.path
  vim.ui.input({
    prompt = "New path: ",
    default = current,
    completion = "file",
  }, function(new_path)
    if not new_path or new_path == "" or new_path == current then
      return
    end
    local old_parent = vim.fn.fnamemodify(current, ":h")
    local success, err = self:_move_path(current, new_path)
    if not success then
      vim.notify("Failed to move/rename: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end
    vim.notify(string.format("Moved/Renamed:\n  %s\n→ %s", current, new_path), vim.log.levels.INFO)
    local new_parent = vim.fn.fnamemodify(vim.fs.normalize(new_path), ":h")
    if vim.fs.normalize(old_parent) ~= vim.fs.normalize(new_parent) then
      prune_fs(self.root_path, old_parent)
    end
    self:refresh()
  end)
end

---@param target_path string
function Tree:find_file(target_path)
  if not target_path or target_path == "" then
    return
  end
  if target_path:sub(1, #self.root_path) ~= self.root_path then
    return
  end

  if self.visible_nodes then
    for i, node in ipairs(self.visible_nodes) do
      if node.path == target_path then
        if self.winid and vim.api.nvim_win_is_valid(self.winid) then
          pcall(vim.api.nvim_win_set_cursor, self.winid, { i, 0 })
        end
        return
      end
    end
  end

  local function expand_recursive(node, target)
    if node.path == target then
      return true
    end
    if node.type == "directory" or node.type == "root" then
      if target:sub(1, #node.path) == node.path then
        if not node.expanded then
          if (node.children and #node.children == 0) or node._unpopulated then
            self:_load_directory(node)
          end
          node.expanded = true
        end
        if node.children then
          for _, child in ipairs(node.children) do
            if expand_recursive(child, target) then
              return true
            end
          end
        end
      end
    end
    return false
  end

  expand_recursive(self.state.root, target_path)
  self._width_manual = false
  self._visible_dirty = true
  self:render()

  for i, node in ipairs(self.visible_nodes) do
    if node.path == target_path then
      if self.winid and vim.api.nvim_win_is_valid(self.winid) then
        pcall(vim.api.nvim_win_set_cursor, self.winid, { i, 0 })
      end
      break
    end
  end
end

---@param node bsi.Node
---@return bsi.Node|nil
function Tree:_find_parent_node(node)
  if not node or node.path == self.root_path then
    return nil
  end

  local function search(current, target_path)
    if not current.children then
      return nil
    end
    for _, child in ipairs(current.children) do
      if child.path == target_path then
        return current
      end
      if child.type == "directory" or child.type == "root" then
        local found = search(child, target_path)
        if found then
          return found
        end
      end
    end
    return nil
  end

  return search(self.state.root, node.path)
end

---@param direction "down"|"up"
function Tree:navigate_file(direction)
  if not self.visible_nodes or #self.visible_nodes == 0 then
    return
  end
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.winid)
  local idx = cursor[1]

  if direction == "down" then
    idx = math.min(idx + 1, #self.visible_nodes)
  else
    idx = math.max(idx - 1, 1)
  end

  vim.api.nvim_win_set_cursor(self.winid, { idx, 0 })

  local node = self.visible_nodes[idx]
  if not node then
    return
  end

  local target = node

  if node.type == "directory" and not node.expanded then
    local current = (direction == "up") and self:_find_parent_node(node) or node

    while current and (current.type == "directory" or current.type == "root") do
      if not current.children or #current.children == 0 or current._unpopulated then
        local scanned = self.provider:scan(current.path, current.depth, {
          show_ignored = self.show_ignored,
        })
        if scanned and scanned.children then
          current.children = scanned.children
          current._unpopulated = false
        end
      end
      local children = current.children or {}
      if #children == 0 then
        break
      end
      current = children[(direction == "up") and #children or 1]
    end

    if current then
      target = current
    end
  end

  if target and target.type == "file" then
    if vim.api.nvim_get_current_win() ~= self.winid then
      vim.api.nvim_set_current_win(self.winid)
    end
    for i, n in ipairs(self.visible_nodes) do
      if n.path == target.path then
        pcall(vim.api.nvim_win_set_cursor, self.winid, { i, 0 })
        break
      end
    end
    self:_open_file()
  end
end

--- Factory
---@param opts table|nil
function M.new(opts)
  return Tree.new(opts)
end

---@param bufnr integer|nil
---@return string|nil
function M.get_root_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.b[bufnr].bsi_tree_root
end

function M.toggle_tree()
  if M.the_tree and M.the_tree.winid and vim.api.nvim_win_is_valid(M.the_tree.winid) then
    safe_close_win(M.the_tree.winid)
    M.the_tree = nil
    return
  end

  local found_win = nil
  local found_buf = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "Tree" then
      found_win = win
      found_buf = buf
      break
    end
  end

  if found_win and found_buf then
    local inst = M.instances[found_buf]
    if inst then
      M.the_tree = inst
    end
    safe_close_win(found_win)
    M.the_tree = nil
    return
  end

  local t = M.new()
  t:open()
  M.the_tree = t

  local opened_path = M.get_opened_file()
  if opened_path ~= "" then
    t:find_file(opened_path)
  end
  vim.cmd("wincmd l")
end

--- Compatibility stub: git-changes mode was removed (laggy on large change sets).
--- Opens / focuses the normal filesystem tree instead.
function M.show_in_git_mode()
  if M.the_tree and M.the_tree.winid and vim.api.nvim_win_is_valid(M.the_tree.winid) then
    return
  end
  M.toggle_tree()
end

function M.set_opened_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].buftype ~= "" then
    return
  end
  local ft = vim.bo[bufnr].filetype
  if ft == "Tree" or ft == "GitView" then
    return
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return
  end
  M.opened_buffer = bufnr
end

function M.get_opened_buffer()
  local buf = M.opened_buffer
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  M.opened_buffer = nil
  return nil
end

function M.get_opened_file()
  local buf = M.get_opened_buffer()
  if buf then
    return vim.api.nvim_buf_get_name(buf) or ""
  end
  return ""
end

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    M.config[k] = v
  end

  M.set_opened_buffer()

  vim.api.nvim_set_hl(0, "BSITreeCurrentFile", { bg = "#3b4261", bold = true })
  vim.api.nvim_set_hl(0, "BSITreeOpenedFile", { fg = "#7aa2f7", italic = true })
  vim.api.nvim_set_hl(0, "BSITreeCursorLine", { bg = "#2e3a4a" })
  vim.api.nvim_set_hl(0, "BSITreeGitIgnored", { fg = "#5c6370", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeGitAdded", { fg = "#9ece6a", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeGitModified", { fg = "#e0af68", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeGitDeleted", { fg = "#f7768e", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeCopied", { fg = "#9ece6a", italic = true })
  vim.api.nvim_set_hl(0, "BSITreeCut", { fg = "#f7768e", italic = true })

  local group = vim.api.nvim_create_augroup("BSITreeTracking", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local buf = args.buf
      M.set_opened_buffer(buf)

      local path = vim.api.nvim_buf_get_name(buf)
      if path == "" or vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "Tree" then
        return
      end

      if path ~= M._last_synced_file then
        M._last_synced_file = path
        for _, tree in pairs(M.instances) do
          if tree.winid and vim.api.nvim_win_is_valid(tree.winid) then
            tree:find_file(path)
          end
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function()
      if M.opened_buffer and not vim.api.nvim_buf_is_valid(M.opened_buffer) then
        M.opened_buffer = nil
      end
      for _, tree in pairs(M.instances) do
        tree:render()
      end
    end,
  })

  vim.api.nvim_create_user_command("BSITree", function(args)
    local root = args.args ~= "" and args.args or nil
    M.new({ root = root }):open()
  end, { nargs = "?", complete = "dir" })
end

M.Renderer = Renderer
M.Tree = Tree

return M
