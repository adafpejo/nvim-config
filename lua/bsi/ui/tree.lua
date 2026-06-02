-- lua/bsi/tree.lua
-- Modern BSI Tree: clean architecture for embedded file tree rendering

local M = {}

M.instances = {}

--- Default configuration for the tree
M.config = {
  -- Whether to show hidden (dot) files/directories and git-ignored files by default.
  -- Can be toggled at runtime with the "h" key inside a tree.
  show_ignored = true,
}

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

--- Creates a new Renderer instance
function Renderer.new()
  return setmetatable({}, Renderer)
end

--- Renders the provided nodes into the buffer with appropriate indentation, icons, and highlights
---@param bufnr integer The buffer to render into
---@param nodes bsi.Node[] The list of nodes to render
---@param winid integer|nil Optional window ID to apply window-local settings
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

  -- Cursor line inside this tree buffer (for live cursor highlighting)
  local cursor_line = -1
  local cur_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(cur_win) and vim.api.nvim_win_get_buf(cur_win) == bufnr then
    local pos = vim.api.nvim_win_get_cursor(cur_win)
    cursor_line = pos[1] - 1  -- 0-based
  end

  for i, node in ipairs(nodes) do
    local indent = string.rep(" ", node.depth)
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
        status_hl = "DiagnosticOk"
        name_hl = "DiagnosticOk"
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
        name_hl = "DiagnosticOk"
        status_hl = "DiagnosticOk"
      elseif gs:sub(1, 10) == "DIR_MULTI:" then
        git_status_prefix = gs:sub(11)
        name_hl = "DiagnosticWarn"
        status_hl = "DiagnosticWarn"
      end
    end

    -- Remove the far-right single-char git status for file lines
    -- (we now show richer colored +N-M detail inline instead)
    if node.type == "file" then
      git_status_prefix = ""
    end

    -- For directories that contain git changes, color the directory name purple
    -- and render the git summary as individual colored letters (A=green, M=orange, D=red) without brackets
    if (node.type == "directory" or node.type == "root") and node.git_status_summary then
      git_status_prefix = ""
      status_hl = nil
      name_hl = "Special" -- purple for directory name when it has git changes
    end

    -- Determine whether we need special git detail coloring
    -- For directories: we use per-letter colors (A=green, M=orange, D=red)
    local detail_hl = nil
    if node.git_status_summary then
      detail_hl = "Special"
    end

    if node.type == "root" or node.type == "directory" then
      if node.expanded then
        if node.children and #node.children == 0 then
          icon = "" -- Empty/Border only
        else
          icon = "" -- Open
        end
        arrow = " "
      else
        icon = "" -- Closed
        arrow = " "
      end
      name_hl = name_hl or "Directory"
    else
      arrow = "  "
      if has_devicons then
        local ic, hl = devicons.get_icon(node.name, vim.fn.fnamemodify(node.name, ":e"), { default = true })
        icon = ic
        icon_hl = hl
      else
        icon = ""
      end
    end

    local gap = " "
    local base_content = indent .. arrow .. icon .. gap .. node.name

    -- Git detail: +N-M for files, AMD letters for directories (no brackets)
    local detail = ""
    if node.type == "file" and node.git_numstat then
      local a = tonumber(node.git_numstat.added) or 0
      local d = tonumber(node.git_numstat.deleted) or 0
      if a > 0 or d > 0 then
        detail = string.format(" +%d-%d", a, d)
      end
    elseif (node.type == "directory" or node.type == "root") and node.git_status_summary then
      detail = " " .. node.git_status_summary
    end
    if detail ~= "" then
      base_content = base_content .. detail
    end

    -- Fixed column for git status (single-char compact indicator)
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

    -- Highlight the line under the cursor (full line)
    if cursor_line == (i - 1) then
      table.insert(highlights, { hl = "BSITreeCursorLine", line = i - 1, col_start = 0, col_end = -1 })
    end

    local current_col = #indent
    local arrow_start = current_col
    local arrow_end = arrow_start + #arrow

    local icon_start = arrow_end
    local icon_end = icon_start + #icon
    local name_start = icon_end + 1   -- after the space between icon and name

    if icon_hl then
      table.insert(highlights, { hl = icon_hl, line = i - 1, col_start = icon_start, col_end = icon_end })
    end

    if name_hl then
      table.insert(highlights, { hl = name_hl, line = i - 1, col_start = name_start, col_end = name_start + #node.name })
    end

    if status_text ~= "" then
      local status_start = #line_content - #status_text
      table.insert(highlights, { hl = status_hl or "Normal", line = i - 1, col_start = status_start, col_end = -1 })
    end

    -- Apply git detail coloring
    if detail ~= "" then
      local detail_start = name_start + #node.name

      if node.git_numstat then
        -- For files: always split +NN (green) and -MM (red)
        -- Example: " +34-23" → +34 in BSITreeGitAdded, -23 in BSITreeGitDeleted
        local plus_idx = detail:find("%+")
        local minus_idx = detail:find("%-")

        if plus_idx then
          local plus_start = detail_start + plus_idx - 1
          local minus_start = minus_idx and (detail_start + minus_idx - 1) or (detail_start + #detail)
          table.insert(highlights, {
            hl = "BSITreeGitAdded", -- green
            line = i - 1,
            col_start = plus_start,
            col_end = minus_start,
          })
        end

        if minus_idx then
          local minus_start = detail_start + minus_idx - 1
          table.insert(highlights, {
            hl = "BSITreeGitDeleted", -- red
            line = i - 1,
            col_start = minus_start,
            col_end = detail_start + #detail,
          })
        end
      elseif detail_hl then
        if node.git_status_summary then
          -- Per-letter coloring for directory git summary: A(green), M(orange), D(red)
          local summary = node.git_status_summary
          for j = 1, #summary do
            local letter = summary:sub(j, j)
            local hl = (letter == "A" and "BSITreeGitAdded")
                    or (letter == "M" and "BSITreeGitModified")
                    or (letter == "D" and "BSITreeGitDeleted")
                    or "Special"

            local letter_col = detail_start + 1 + (j - 1)  -- after the leading space
            table.insert(highlights, {
              hl = hl,
              line = i - 1,
              col_start = letter_col,
              col_end = letter_col + 1,
            })
          end
        else
          -- Fallback for other directory cases (single color)
          table.insert(highlights, {
            hl = detail_hl,
            line = i - 1,
            col_start = detail_start,
            col_end = detail_start + #detail,
          })
        end
      end
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

--- Creates a new Provider instance for scanning the filesystem
function Provider.new() return setmetatable({}, Provider) end

--- Fetches git status information for all files within the specified root directory
---@param root string The directory to check for git status
---@return table|nil A map of file paths to their git status information
function Provider:_get_git_changes(root)
  -- Normalize the requested tree root
  local req_root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
  -- Resolve symlinks (important on macOS where /var -> /private/var)
  req_root = vim.fn.resolve(req_root):gsub("/$", "")

  local git_root_cmd = "git -C " .. vim.fn.shellescape(req_root) .. " rev-parse --show-toplevel 2>/dev/null"
  local handle_root = io.popen(git_root_cmd)
  if not handle_root then return nil end
  local git_root = handle_root:read("*l")
  handle_root:close()
  if not git_root or git_root == "" then return nil end
  git_root = vim.fn.fnamemodify(git_root, ":p"):gsub("/$", "")
  git_root = vim.fn.resolve(git_root):gsub("/$", "")

  local cmd = "git -C " .. vim.fn.shellescape(git_root) .. " status --porcelain"
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()

  if result == "" then return nil end

  local changes = {}
  changes[git_root] = { status = "dir" }

  -- Helper: is this path under the user's requested tree root?
  local function under_req(p)
    return p == req_root or p:sub(1, #req_root + 1) == req_root .. "/"
  end

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
            if under_req(p) then
              changes[p] = { status = "??" }
            end
            local h = vim.loop.fs_scandir(p)
            if h then
                while true do
                    local name, type = vim.loop.fs_scandir_next(h)
                    if not name then break end
                    local fp = p .. "/" .. name
                    if type == "directory" then
                        mark_untracked(fp)
                    else
                        if under_req(fp) then
                          changes[fp] = { status = "??" }
                        end
                    end
                end
            end
        end
        mark_untracked(fullpath)
    else
        if under_req(fullpath) then
          changes[fullpath] = { status = status }
          local current = fullpath
          while #current > #git_root do
            current = vim.fn.fnamemodify(current, ":h")
            if not changes[current] then changes[current] = { status = "dir" }
            elseif changes[current].status ~= "dir" then break end
            if current == git_root then break end
          end
        end
    end
  end
  return changes
end

--- Fetches git numstat (+added/-deleted lines) for files in the repo.
--- Runs both `git diff --numstat` (unstaged) and `git diff --cached --numstat` (staged) and merges results.
---@param root string The directory to check
---@return table|nil Map of absolute file path -> {added: integer, deleted: integer}
function Provider:_get_git_numstats(root)
  root = root:gsub("/$", "")
  local git_root_cmd = { "git", "-C", root, "rev-parse", "--show-toplevel" }
  local git_root = vim.fn.system(git_root_cmd)
  if vim.v.shell_error ~= 0 then return nil end
  git_root = vim.trim(git_root)
  if git_root == "" then return nil end

  local stats = {}

  local function parse_and_merge(output)
    for line in output:gmatch("[^\r\n]+") do
      -- <added>\t<deleted>\t<path>
      local added_str, deleted_str, path = line:match("^(%S+)%s+(%S+)%s+(.+)$")
      if not added_str or not deleted_str or not path then goto continue end

      -- Handle renames: "old => new" or "old => new" with quotes
      if path:match(" => ") then
        path = vim.split(path, " => ")[2] or path
      end
      if path:match('^"') then
        path = path:match('^"(.*)"$') or path
      end

      local added = (added_str == "-") and 0 or (tonumber(added_str) or 0)
      local deleted = (deleted_str == "-") and 0 or (tonumber(deleted_str) or 0)

      local fullpath = (git_root .. "/" .. path):gsub("/$", "")

      if stats[fullpath] then
        stats[fullpath].added = stats[fullpath].added + added
        stats[fullpath].deleted = stats[fullpath].deleted + deleted
      else
        stats[fullpath] = { added = added, deleted = deleted }
      end
      ::continue::
    end
  end

  -- Unstaged changes
  local out1 = vim.fn.system({ "git", "-C", git_root, "diff", "--numstat" })
  if vim.v.shell_error == 0 and out1 ~= "" then
    parse_and_merge(out1)
  end

  -- Staged changes
  local out2 = vim.fn.system({ "git", "-C", git_root, "diff", "--cached", "--numstat" })
  if vim.v.shell_error == 0 and out2 ~= "" then
    parse_and_merge(out2)
  end

  return next(stats) and stats or nil
end

--- Checks if a file or directory name matches any of the patterns in DEFAULT_IGNORE
---@param name string The name of the file or directory
---@return boolean True if the name should be ignored
function Provider:_should_ignore(name)
  for _, pattern in ipairs(DEFAULT_IGNORE) do
    if name:match(pattern) then return true end
  end
  return false
end

--- Determines whether a path should be skipped based on hidden/gitignore settings.
---@param fullpath string
---@param name string
---@param opts table|nil { show_ignored = boolean }
function Provider:_should_skip(fullpath, name, opts)
  opts = opts or {}
  local show_ignored = opts.show_ignored == true

  if not show_ignored then
    -- Apply hardcoded ignores (including .git) only when not showing ignored
    for _, pattern in ipairs(DEFAULT_IGNORE) do
      if name:match(pattern) then
        return true
      end
    end

    -- Hidden files/directories (dotfiles)
    if name:match("^%.") then
      return true
    end

    -- Git ignored
    if self:_is_git_ignored(fullpath) then
      return true
    end
  end

  return false
end

--- Checks if a path is ignored according to .gitignore (cached).
function Provider:_is_git_ignored(fullpath)
  self._ignored_cache = self._ignored_cache or {}

  if self._ignored_cache[fullpath] ~= nil then
    return self._ignored_cache[fullpath]
  end

  -- Determine git root (cached)
  if self._git_root == nil then
    local dir = vim.fn.fnamemodify(fullpath, ":h")
    local out = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
    if vim.v.shell_error == 0 and out[1] then
      self._git_root = vim.trim(out[1])
    else
      self._git_root = false
    end
  end

  if not self._git_root then
    self._ignored_cache[fullpath] = false
    return false
  end

  local cmd = { "git", "-C", self._git_root, "check-ignore", "-q", "--", fullpath }
  vim.fn.system(cmd)
  local is_ignored = (vim.v.shell_error == 0)

  self._ignored_cache[fullpath] = is_ignored
  return is_ignored
end

--- Recursively scans a directory path to build a tree structure of bsi.Node objects
---@param path string The directory path to scan
---@param depth integer Current recursion depth
---@param opts table Scanning options (expand_all, git_only, git_changes, git_numstats)
---@return bsi.Node|nil The root node of the scanned subtree
function Provider:scan(path, depth, opts)
  depth = depth or 0
  opts = opts or {}
  local git_changes = opts.git_changes
  local git_only = opts.git_only
  local git_numstats = opts.git_numstats

  if git_only and git_changes and not git_changes[path] then return nil end

  local node_gs = (git_changes and git_changes[path] and git_changes[path].status ~= "dir") and git_changes[path].status or nil

  local node = {
    id = path,
    name = vim.fn.fnamemodify(path, ":t") or path,
    path = path,
    type = depth == 0 and "root" or "directory",
    depth = depth,
    expanded = opts.expand_all or (depth == 0),
    children = {},
    git_status = node_gs,
  }

  local children_map = {}
  local handle = vim.loop.fs_scandir(path)
  if handle then
    while true do
      local name = vim.loop.fs_scandir_next(handle)
      if not name then break end
      local full = path .. "/" .. name
      if not self:_should_skip(full, name, opts) then
        children_map[name] = true
      end
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
    local numstat = git_numstats and git_numstats[fullpath] or nil
    local child
    if is_dir then
      child = self:scan(fullpath, depth + 1, opts)
      if child then
        if git_only and #child.children == 0 then goto continue end
        child.expanded = opts.expand_all or false
      else goto continue end
    else
      child = { id = fullpath, name = name, path = fullpath, type = "file", depth = depth + 1, expanded = false, children = nil, git_status = g_status ~= "dir" and g_status or nil, git_numstat = numstat }
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

  -- Build canonical directory summary for postfix [DMA] etc.
  if git_changes and node.type == "directory" and node.children then
    local has = { A = false, M = false, D = false }
    local function mark(s)
      if not s then return end
      if s == "DIR_ADDED" then has.A = true; return end
      if s == "DIR_UNTRACKED" then has.A = true; return end
      if s == "DIR_PARTIAL" then has.A = true; has.M = true; return end
      if s:sub(1, 10) == "DIR_MULTI:" then
        local rest = s:sub(11)
        if rest:match("A") or rest:match("%?") then has.A = true end
        if rest:match("[MRC]") then has.M = true end
        if rest:match("D") then has.D = true end
        return
      end
      -- porcelain 2-char or single char
      if s:match("A") or s:match("%?") then has.A = true end
      if s:match("[MRC]") then has.M = true end
      if s:match("D") then has.D = true end
    end
    for _, c in ipairs(node.children) do
      mark(c.git_status)
      if c.git_status_summary then
        if c.git_status_summary:match("A") then has.A = true end
        if c.git_status_summary:match("M") then has.M = true end
        if c.git_status_summary:match("D") then has.D = true end
      end
    end
    local summary = ""
    if has.D then summary = summary .. "D" end
    if has.M then summary = summary .. "M" end
    if has.A then summary = summary .. "A" end
    if summary ~= "" then
      node.git_status_summary = summary
    end
  end

  table.sort(node.children, function(a, b)
    -- Directories before files
    if a.type ~= b.type then
      return a.type == "directory"
    end

    -- Within directories: special ordering for dot directories
    if a.type == "directory" then
      local function dir_priority(name)
        if name == ".git" then return 0 end          -- .git always first
        if name:sub(1, 1) == "." then return 1 end    -- other dot directories next
        return 2                                       -- regular directories last
      end

      local pa = dir_priority(a.name)
      local pb = dir_priority(b.name)
      if pa ~= pb then
        return pa < pb
      end

      -- Same priority group: sort alphabetically (case-insensitive)
      return a.name:lower() < b.name:lower()
    end

    -- Files: alphabetical (case-insensitive)
    return a.name:lower() < b.name:lower()
  end)

  if node.type == "directory" and #node.children == 1 and node.children[1].type == "directory" then
    local child = node.children[1]
    node.name = node.name .. "/" .. child.name
    node.children = child.children
    node.path = child.path
    node.id = child.id
    node.git_status = child.git_status
    node.git_status_summary = child.git_status_summary
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

--- Creates a new Tree instance and performs initial scan
---@param opts table Tree options (root, expand_all, git_only, bufnr, winid, show_ignored)
---        show_ignored defaults to M.config.show_ignored (true by default)
function Tree.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Tree)
  self.provider = Provider.new()
  self.renderer = Renderer.new()
  local raw_root = opts.root or vim.fn.getcwd()
  self.root_path = vim.fn.resolve(vim.fn.fnamemodify(raw_root, ":p")):gsub("/$", "")
  self.opts = opts
  -- Per-instance option takes precedence, otherwise fall back to global config (default true)
  if opts.show_ignored ~= nil then
    self.show_ignored = opts.show_ignored
  else
    self.show_ignored = M.config.show_ignored
  end
  local scan_opts = {
    expand_all = opts.expand_all,
    git_only = opts.git_only,
    show_ignored = self.show_ignored,
  }
  scan_opts.git_changes = self.provider:_get_git_changes(self.root_path)
  scan_opts.git_numstats = self.provider:_get_git_numstats(self.root_path)
  self._git_changes = scan_opts.git_changes
  self._git_numstats = scan_opts.git_numstats
  local root_node = self.provider:scan(self.root_path, 0, scan_opts)
  self.state = { root = root_node or { id = self.root_path, name = vim.fn.fnamemodify(self.root_path, ":t"), path = self.root_path, type = "root", depth = 0, expanded = true, children = {} } }

  -- For git-only views (used by <leader>ge and layout u2), auto-expand directories that
  -- contain changes so the user immediately sees the modified / untracked files.
  if opts.git_only then
    self:_expand_changed_dirs()
  end

  self.bufnr = opts.bufnr
  self.winid = opts.winid
  return self
end

--- Returns the root path of the tree formatted for display (home-relative)
---@return string
function Tree:get_root_path() return vim.fn.fnamemodify(self.root_path, ":~") end

--- Flattens the tree structure into a list of nodes that are currently visible (based on expansion state)
---@return bsi.Node[]
function Tree:get_visible_nodes()
  local nodes = {}
  local function walk(node)
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

--- Updates the tree buffer by flattening the state and calling the renderer
function Tree:render()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end
  self.visible_nodes = self:get_visible_nodes()
  local render_nodes = {}
  for _, node in ipairs(self.visible_nodes) do
    local n = vim.deepcopy(node)
    if n.type ~= "root" then
      n.depth = n.depth - 1
    end
    table.insert(render_nodes, n)
  end
  self.renderer:render(self.bufnr, render_nodes, self.winid)
end

--- Opens the tree in a side window, sets up the buffer, and registers keybindings
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

  -- Set winbar (will be "Git: ..." if in git mode)
  self:_update_winbar()

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
  map("h", function() self:toggle_show_ignored() end, "Toggle hidden & git-ignored files/dirs")
  map("q", "<cmd>close<cr>", "Close")
  map("<CR>", function() self:toggle() end, "Toggle / Expand directory")
  map("o", function() self:_open_file() end, "Open file")
  map("d", function() self:_diff_file() end, "Diff file")
  map("g", function() self:toggle_git_mode() end, "Toggle git changes view (same buffer)")
  map("a", function() self:_add_file() end, "Add new file in current directory")
  map("r", function() self:rename_or_move() end, "Rename / Move file or directory")
  map("u", function() self:rename_or_move() end, "Rename / Move file or directory")
  map("y", function() self:_yank(false) end, "Yank name")
  map("Y", function() self:_yank(true) end, "Yank relative path")
  map("<LeftMouse>", "<LeftMouse>", "Select node")
  map("<2-LeftMouse>", function() self:toggle() end, "Open file / Toggle directory (double-click)")
end

--- Re-scans the filesystem and updates the tree state while attempting to preserve current expansion
function Tree:refresh()
  -- Clear gitignore caches on refresh
  if self.provider then
    self.provider._ignored_cache = {}
    self.provider._git_root = nil
  end

  local expanded = {}
  local function collect(node)
    if node.expanded then expanded[node.id] = true end
    if node.children then for _, child in ipairs(node.children) do collect(child) end end
  end
  collect(self.state.root)
  local scan_opts = {
    expand_all = self.opts.expand_all,
    git_only = self.opts.git_only,
    show_ignored = self.show_ignored,
  }
  scan_opts.git_changes = self.provider:_get_git_changes(self.root_path)
  scan_opts.git_numstats = self.provider:_get_git_numstats(self.root_path)
  self._git_changes = scan_opts.git_changes
  self._git_numstats = scan_opts.git_numstats
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

--- Toggles visibility of hidden (dot) files and git-ignored files/directories
function Tree:toggle_show_ignored()
  self.show_ignored = not (self.show_ignored or false)

  -- Clear caches so gitignore checks are re-evaluated
  if self.provider then
    self.provider._ignored_cache = {}
    self.provider._git_root = nil
  end

  self:refresh()
end

--- Updates the window title (winbar) to reflect current root and view mode (e.g. git).
function Tree:_update_winbar()
  local ok, ctx = pcall(require, "bsi.ui.context")
  if not ok or not ctx or not ctx.render_title then return end
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then return end

  local title = self:get_root_path()
  if self.opts and self.opts.git_only then
    title = "Git: " .. title
  end
  vim.wo[self.winid].winbar = ctx.render_title(title)
end

--- Toggles between full filesystem view and git-changes-only view (same buffer, like normal/insert mode).
function Tree:toggle_git_mode()
  self.opts = self.opts or {}
  self.opts.git_only = not (self.opts.git_only or false)

  -- Clear git caches so status is re-queried for the new mode
  if self.provider then
    self.provider._ignored_cache = {}
    self.provider._git_root = nil
  end

  self:refresh()

  if self.opts.git_only then
    self:_expand_changed_dirs()
    self:render()
  end

  self:_update_winbar()
end

--- Internal: expand directories that have git changes (used for git mode UX).
function Tree:_expand_changed_dirs()
  local function expand_changed(node)
    local has_change = node.git_status
      or (node.git_status_summary and node.git_status_summary ~= "")
      or (node.git_numstat and ((node.git_numstat.added or 0) + (node.git_numstat.deleted or 0) > 0))
    if has_change and (node.type == "directory" or node.type == "root") then
      node.expanded = true
    end
    if node.children then
      for _, child in ipairs(node.children) do expand_changed(child) end
    end
  end
  expand_changed(self.state.root)
end

--- Toggles the expansion state of the directory under the cursor or opens the file
function Tree:toggle()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
  if not node or node.type == "file" then self:_open_file() return end
  if not node.expanded and node.type == "directory" and node.children and #node.children == 0 then
    local scan_opts = {
      git_changes = self._git_changes,
      git_numstats = self._git_numstats,
      show_ignored = self.show_ignored,
    }
    local scanned = self.provider:scan(node.path, node.depth, scan_opts)
    node.children = scanned.children
  end
  node.expanded = not node.expanded
  self:render()
end

--- Opens the file under the cursor in the previous window
function Tree:_open_file()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
  if not node or node.type ~= "file" then return end
  vim.cmd("wincmd l")
  vim.cmd("edit " .. vim.fn.fnameescape(node.path))
end

--- Opens a git diff view for the file under the cursor
function Tree:_diff_file()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
  if not node or node.type ~= "file" then return end
  vim.cmd("DiffviewOpen -- " .. vim.fn.fnameescape(node.path))
end

--- Yanks the name or relative path of the node under the cursor to the clipboard
---@param full boolean If true, yanks the relative path from root; otherwise yanks only the name
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

--- Prompts for a filename and creates a new (empty) file under the directory
--- containing the node under the cursor. Supports nested paths (e.g. "foo/bar.txt").
function Tree:_add_file()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local node = self.visible_nodes[cursor[1]]
  if not node then return end

  local target_dir = (node.type == "directory" or node.type == "root")
      and node.path
      or vim.fn.fnamemodify(node.path, ":h")

  vim.ui.input({
    prompt = "New file (in " .. vim.fn.fnamemodify(target_dir, ":~:.") .. "): ",
  }, function(name)
    if not name or name == "" then return end

    local new_path = vim.fs.normalize(target_dir .. "/" .. name)

    -- Create parent directories if the user typed a nested path
    local parent = vim.fn.fnamemodify(new_path, ":h")
    if vim.fn.isdirectory(parent) == 0 then
      vim.fn.mkdir(parent, "p")
    end

    if vim.fn.filereadable(new_path) == 1 then
      vim.notify("File already exists: " .. new_path, vim.log.levels.WARN)
      return
    end

    local fd = io.open(new_path, "w")
    if not fd then
      vim.notify("Failed to create file: " .. new_path, vim.log.levels.ERROR)
      return
    end
    fd:close()

    self:refresh()
    self:find_file(new_path)

    -- Switch to main window and open the new file
    vim.schedule(function()
      vim.cmd("wincmd l")
      vim.cmd("edit " .. vim.fn.fnameescape(new_path))
    end)
  end)
end

--- Internal: robustly move or rename a path (handles directories with contents)
---@param src string
---@param dst string
---@return boolean success
---@return string|nil error
function Tree:_move_path(src, dst)
  local stat = vim.loop.fs_stat(src)
  if not stat then
    return false, "Source does not exist"
  end

  -- Fast path: try atomic rename first
  local ok, err = vim.loop.fs_rename(src, dst)
  if ok then
    return true
  end

  -- Ensure parent directory of destination exists (important for moves into new folders)
  vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")

  -- For files, try copy + delete as fallback (e.g. cross-device move)
  if stat.type == "file" then
    local content = vim.fn.readfile(src, "b")
    vim.fn.writefile(content, dst, "b")
    vim.loop.fs_unlink(src)
    return true
  end

  -- Directory: recursive move
  if stat.type == "directory" then
    -- Ensure parent directory of destination exists
    vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")

    -- Create destination directory
    if not vim.loop.fs_stat(dst) then
      local mkdir_ok = vim.loop.fs_mkdir(dst, 493) -- 0755
      if not mkdir_ok then
        return false, "Failed to create destination directory"
      end
    end

    -- Move all children recursively
    local handle = vim.loop.fs_scandir(src)
    if handle then
      while true do
        local name, _ = vim.loop.fs_scandir_next(handle)
        if not name then break end
        local child_src = src .. "/" .. name
        local child_dst = dst .. "/" .. name
        local success, move_err = self:_move_path(child_src, child_dst)
        if not success then
          return false, move_err
        end
      end
    end

    -- Remove the now-empty source directory
    vim.loop.fs_rmdir(src)
    return true
  end

  return false, "Unsupported file type: " .. stat.type
end

--- Rename or move the node under the cursor (like nvim-tree "u" / rename)
function Tree:rename_or_move()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end

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

    local success, err = self:_move_path(current, new_path)
    if not success then
      vim.notify("Failed to move/rename: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end

    vim.notify(string.format("Moved/Renamed:\n  %s\n→ %s", current, new_path), vim.log.levels.INFO)
    self:refresh()
  end)
end

--- Locates a specific file path in the tree, expanding directories as needed to make it visible
---@param target_path string The absolute path of the file to find
function Tree:find_file(target_path)
  if not target_path or target_path == "" then return end
  if target_path:sub(1, #self.root_path) ~= self.root_path then return end

  local function expand_recursive(node, target)
    if node.path == target then return true end
    if node.type == "directory" or node.type == "root" then
      if target:sub(1, #node.path) == node.path then
        if not node.expanded then
          if node.children and #node.children == 0 then
            local scan_opts = {
              git_changes = self._git_changes,
              git_numstats = self._git_numstats,
              show_ignored = self.show_ignored,
            }
            local scanned = self.provider:scan(node.path, node.depth, scan_opts)
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

--- Find the parent of a node by walking the tree (nodes do not store parent refs)
---@param node bsi.Node
---@return bsi.Node|nil
function Tree:_find_parent_node(node)
  if not node or node.path == self.root_path then return nil end

  local function search(current, target_path)
    if not current.children then return nil end
    for _, child in ipairs(current.children) do
      if child.path == target_path then
        return current
      end
      if child.type == "directory" or child.type == "root" then
        local found = search(child, target_path)
        if found then return found end
      end
    end
    return nil
  end

  return search(self.state.root, node.path)
end

--- Implements "next/prev file" navigation mirroring the NvimTree <C-j>/<C-k> behavior.
--- Moves one step in the current visible list, and if landing on a collapsed directory,
--- descends (first child for down, last child for up) to find a file to open.
--- Does not mutate expansion state.
---@param direction "down"|"up"
function Tree:navigate_file(direction)
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then return end

  local cursor = vim.api.nvim_win_get_cursor(self.winid)
  local idx = cursor[1]

  if direction == "down" then
    idx = math.min(idx + 1, #self.visible_nodes)
  else
    idx = math.max(idx - 1, 1)
  end

  vim.api.nvim_win_set_cursor(self.winid, { idx, 0 })

  local node = self.visible_nodes[idx]
  if not node then return end

  local target = node

  if node.type == "directory" and not node.expanded then
    local current = (direction == "up") and self:_find_parent_node(node) or node

    while current and (current.type == "directory" or current.type == "root") do
      if not current.children or #current.children == 0 then
        -- lazy populate if somehow empty (defensive)
        local scan_opts = {
          git_changes = self._git_changes,
          git_numstats = self._git_numstats,
          show_ignored = self.show_ignored,
        }
        local scanned = self.provider:scan(current.path, current.depth, scan_opts)
        if scanned and scanned.children then
          current.children = scanned.children
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
    -- Ensure we are operating from the tree window (required for wincmd l in _open_file)
    if vim.api.nvim_get_current_win() ~= self.winid then
      vim.api.nvim_set_current_win(self.winid)
    end
    -- Best-effort: position cursor on the target if it is currently visible
    for i, n in ipairs(self.visible_nodes) do
      if n.path == target.path then
        pcall(vim.api.nvim_win_set_cursor, self.winid, { i, 0 })
        break
      end
    end
    self:_open_file()
    self:render()  -- update cursor line highlight etc in the tree view
  end
end

--- Factory method to create a new Tree instance
---@param opts table|nil Tree options. `show_ignored` defaults to the value set in `M.setup()`.
function M.new(opts) return Tree.new(opts) end

--- Retrieves the root path associated with a tree buffer
---@param bufnr integer|nil The buffer number (defaults to current)
---@return string|nil
function M.get_root_path(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.b[bufnr].bsi_tree_root
end

--- Toggles the visibility of the BSI tree window (the same tree buffer; mode is independent).
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

--- Ensures a BSI tree is visible and switched to git-changes mode (same buffer, like a view mode).
--- If no tree is open, opens one directly in git mode.
--- Mapped to <leader>ge.
function M.show_in_git_mode()
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
    local t = M.instances[found_buf]
    if t then
      if not (t.opts and t.opts.git_only) then
        t:toggle_git_mode()
      end
      vim.api.nvim_set_current_win(found_win)
    end
  else
    local t = M.new({ git_only = true })
    t:open()
  end
end

--- Initializes global tree settings, highlights, autocommands, and user commands
---@param opts table|nil Configuration options (e.g. { show_ignored = true })
function M.setup(opts)
  opts = opts or {}
  -- Merge user options into the global config
  for k, v in pairs(opts) do
    M.config[k] = v
  end

  vim.api.nvim_set_hl(0, "BSITreeCurrentFile", { bg = "#3b4261", bold = true })
  vim.api.nvim_set_hl(0, "BSITreeOpenedFile", { fg = "#7aa2f7", italic = true })
  vim.api.nvim_set_hl(0, "BSITreeCursorLine", { bg = "#2e3a4a" })  -- cursor line inside the tree (full line)

  -- Git change type colors for inline file detail (+N-M)
  -- bg = "NONE" prevents interference with the current-file background highlight
  vim.api.nvim_set_hl(0, "BSITreeGitAdded",    { fg = "#9ece6a", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeGitModified", { fg = "#e0af68", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeGitDeleted",  { fg = "#f7768e", bg = "NONE" })

  local group = vim.api.nvim_create_augroup("BSITreeTracking", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local buf = args.buf

      -- When focusing the BSI Tree buffer itself, do a full refresh
      -- (re-scan filesystem + git status/numstat, preserve expansion, then render).
      if M.instances[buf] then
        local tree = M.instances[buf]
        if tree.winid and vim.api.nvim_win_is_valid(tree.winid) then
          tree:refresh()
        end
      end

      local path = vim.api.nvim_buf_get_name(buf)
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

  -- Live cursor line highlight inside the tree
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function(args)
      local buf = args.buf
      if vim.bo[buf].filetype == "Tree" then
        local tree = M.instances[buf]
        if tree and tree.winid and vim.api.nvim_win_is_valid(tree.winid) then
          tree:render()
        end
      end
    end,
  })

  vim.api.nvim_create_user_command("BSITree", function(args)
    local root = args.args ~= "" and args.args or nil
    M.new({ root = root }):open()
  end, { nargs = "?", complete = "dir" })
end

return M
