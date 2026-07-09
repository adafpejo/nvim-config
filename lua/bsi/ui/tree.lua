-- lua/bsi/tree.lua
-- Modern BSI Tree: clean architecture for embedded file tree rendering

local M = {}

M.instances = {}

-- One-time namespace for all extmarks (cheaper than create_namespace on every render)
local ns_id = vim.api.nvim_create_namespace("bsitree")

-- Track last opened file path we synced trees to, to avoid redundant find_file+render
-- on every BufEnter (only pay when user actually switched main editing file)
M._last_synced_file = ""

-- "The one" main BSI tree instance for <leader>ee / <leader>ge.
-- This ensures ee/ge always operate on the same dedicated tree buffer (mode can still be switched with 'g' inside).
M.the_tree = nil

-- Tracked "opened buffer": the single main editing buffer the user is working with.
-- (User works only with one buffer at a time for editing.)
-- Used for current-file highlighting in trees and find_file syncing, instead of
-- scanning all windows (avoids picking tree buffers or wrong splits when focused on tree).
M.opened_buffer = nil

--- Default configuration for the tree
M.config = {
  -- show_ignored controls visibility of gitignored items (shown gray when true).
  -- Dotfiles (names starting with ".") are *always* included in the tree.
  -- Default false still filters gitignored entries early in the fs_scandir loop.
  -- The snapshot (via bsi.git.status runner + Project) is *always* collected now so
  -- that hiding uses the full optimizations: early filter before node creation (#1),
  -- path_ignored short-circuit + negative toplevel cache (#2), parent_ignored prop (#4),
  -- precomputed dirs, one-shot correct command, etc. Toggle with 'h'.
  show_ignored = false,
}

local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local system = require("bsi.system")
local Cmd = require("bsi.cmd")

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

  -- Small indent cache (depths are small in practice)
  local indent_cache = { ["0"] = "", ["1"] = " ", ["2"] = "  ", ["3"] = "   ", ["4"] = "    " }

  -- Use the tracked opened buffer (the single one the user works with).
  -- This is set in setup's BufEnter and is reliable even when the tree sidebar
  -- itself is focused (avoids the old window scan picking the tree buf or wrong split).
  local current_file = M.get_opened_file()

  for i, node in ipairs(nodes) do
    -- Visible nodes never include root; their depth starts at 1 for top-level children.
    -- Subtract 1 for display indent so first level has no leading spaces.
    local display_depth = node.depth - 1
    if display_depth < 0 then display_depth = 0 end
    local indent = indent_cache[tostring(display_depth)] or string.rep(" ", display_depth)
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

    if node.git_ignored then
      name_hl = "BSITreeGitIgnored"
      status_hl = nil
      if icon_hl then
        icon_hl = "BSITreeGitIgnored"
      end
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
      if node._icon then
        icon = node._icon
        icon_hl = node._icon_hl
      elseif has_devicons then
        -- Fallback (should not normally happen)
        local ic, hl = devicons.get_icon(node.name, vim.fn.fnamemodify(node.name, ":e"), { default = true })
        icon = ic
        icon_hl = hl
      else
        icon = ""
      end
    end

    -- Build line with table.concat (fewer temp strings)
    local gap = " "
    local parts = { indent, arrow, icon, gap, node.name }

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
      parts[#parts + 1] = detail
    end

    local base_content = table.concat(parts)

    -- Status prefix for directories (single char). We keep a lightweight right-ish placement
    -- instead of expensive rigid padding for every line.
    local status_text = git_status_prefix
    local line_content = base_content
    if status_text ~= "" then
      -- Minimal separator instead of fixed-column padding (cheaper + simpler)
      line_content = base_content .. "  " .. status_text
    end

    table.insert(lines, line_content)

    if is_current then
      table.insert(highlights, { hl = "BSITreeCurrentFile", line = i - 1, col_start = 0, col_end = -1 })
    end

    local current_col = #indent
    local arrow_start = current_col
    local arrow_end = arrow_start + #arrow

    local icon_start = arrow_end
    local icon_end = icon_start + #icon
    local name_start = icon_end + 1   -- after the space between icon and name

    if node.git_ignored then
      -- Combine icon + name into single grey hl for ignored items.
      -- Reduces nvim_buf_add_highlight calls significantly for huge ignored subtrees
      -- (e.g. node_modules) when user explicitly opens the ignored dir.
      local content_start = arrow_end
      local content_end = name_start + #node.name
      table.insert(highlights, { hl = "BSITreeGitIgnored", line = i - 1, col_start = content_start, col_end = content_end })
      icon_hl = nil
      name_hl = nil
    end

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
      -- detail_start is right after the node name in the final line
      local name_end = name_start + #node.name
      local detail_start = name_end

      if node.git_numstat then
        -- We control the format " +A-D" so we can compute offsets directly (no find)
        -- detail example: " +12-3"  -> positions relative: 1:' ',2:'+', ...
        if detail:sub(2,2) == "+" then
          -- +NN starts at detail_start + 1
          local plus_start = detail_start + 1
          local dash = detail:find("%-", 3, true) or (#detail + 1)
          local minus_start = detail_start + dash - 1
          table.insert(highlights, {
            hl = "BSITreeGitAdded",
            line = i - 1,
            col_start = plus_start,
            col_end = minus_start,
          })
          if dash then
            table.insert(highlights, {
              hl = "BSITreeGitDeleted",
              line = i - 1,
              col_start = minus_start,
              col_end = detail_start + #detail,
            })
          end
        end
      elseif detail_hl and node.git_status_summary then
        -- Per-letter coloring for directory git summary: A(green), M(orange), D(red)
        local summary = node.git_status_summary
        for j = 1, #summary do
          local letter = summary:sub(j, j)
          local hl = (letter == "A" and "BSITreeGitAdded")
                  or (letter == "M" and "BSITreeGitModified")
                  or (letter == "D" and "BSITreeGitDeleted")
                  or "Special"

          local letter_col = detail_start + 1 + (j - 1)
          table.insert(highlights, {
            hl = hl,
            line = i - 1,
            col_start = letter_col,
            col_end = letter_col + 1,
          })
        end
      elseif detail_hl then
        table.insert(highlights, {
          hl = detail_hl,
          line = i - 1,
          col_start = detail_start,
          col_end = detail_start + #detail,
        })
      end
    end
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, hl.hl, hl.line, hl.col_start, hl.col_end)
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

local DEFAULT_IGNORE = { "node_modules$", "^vendor$", "^dist$", "^build$", "^target$" }

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

--- Collects the set of git-ignored paths (and directory prefixes) for a root in one shot.
--- Uses `git status --porcelain=v1 -z --ignored=matching` so we get "!!" entries without
--- N separate `git check-ignore` calls. Combined with parent/under_ignored propagation
--- and the existing shallow logic, this makes the per-node gitignore decision O(1) Lua
--- for the vast majority of entries (huge wins on node_modules, vendor, etc.).
---@param root string
---@return table|nil  Map of absolute path -> true for directly reported ignored paths.
function Provider:_get_git_ignored_snapshot(root)
  -- Legacy sync path. Prefer the centralized runner from the plan implementation.
  local git = require("bsi.git")
  if git.is_git_integration_enabled and git.is_git_integration_enabled() then
    local map = git.run_git_status and git.run_git_status(root) or nil
    if map then
      local ignored = {}
      for p, xy in pairs(map) do
        if xy == "!!" then ignored[p] = true end
      end
      return next(ignored) and ignored or nil
    end
  end

  -- Fallback (should almost never be reached now)
  local req_root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
  req_root = vim.fn.resolve(req_root):gsub("/$", "")

  local git_root_cmd = "git -C " .. vim.fn.shellescape(req_root) .. " rev-parse --show-toplevel 2>/dev/null"
  local handle_root = io.popen(git_root_cmd)
  if not handle_root then return nil end
  local git_root = handle_root:read("*l")
  handle_root:close()
  if not git_root or git_root == "" then return nil end
  git_root = vim.fn.fnamemodify(git_root, ":p"):gsub("/$", "")
  git_root = vim.fn.resolve(git_root):gsub("/$", "")

  -- Include ignored entries (status "!!"). -z for robustness; we normalize later.
  -- NOTE: this fallback is missing --no-optional-locks / -u that the plan+new runner use.
  local cmd = "git -C " .. vim.fn.shellescape(git_root) .. " status --porcelain=v1 -z --ignored=matching"
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()

  if result == "" then return nil end

  local ignored = {}
  for entry in vim.gsplit(result, "\0", { plain = true, trimempty = true }) do
    if entry == "" then goto continue end
    local status = entry:sub(1, 2)
    local path = entry:sub(4)
    if path:match('^"') then path = path:match('^"(.*)"$') or path end
    if status == "!!" and path and path ~= "" then
      local full = (git_root .. "/" .. path):gsub("/+$", "")
      ignored[full] = true
    end
    ::continue::
  end

  return next(ignored) and ignored or nil
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

  -- .git is always excluded (never useful to show, and expensive to traverse).
  if name == ".git" then
    return true
  end

  if not show_ignored then
    -- Apply other hardcoded ignores only when not showing ignored.
    -- Dotfiles (names starting with ".") are always included (except .git above).
    for _, pattern in ipairs(DEFAULT_IGNORE) do
      if name:match(pattern) then
        return true
      end
    end

    -- Git ignored (controlled by show_ignored toggle)
    if self:_is_git_ignored(fullpath) then
      return true
    end
  end

  return false
end

--- Checks if a path is ignored according to .gitignore (cached).
--- When the gitignore feature is disabled (show_ignored=false by default), this
--- short-circuits and never does git work — only the cheap DEFAULT_IGNORE name
--- patterns are filtered. Dotfiles are always added.
function Provider:_is_git_ignored(fullpath)
  self._ignored_cache = self._ignored_cache or {}

  if self._ignored_cache[fullpath] ~= nil then
    return self._ignored_cache[fullpath]
  end

  -- If no snapshot was collected, it means the gitignore feature is currently
  -- disabled in config. Treat nothing as git-ignored here (avoid any cost).
  if not self._ignored_snapshot then
    self._ignored_cache[fullpath] = false
    return false
  end

  -- Fast path from one-shot snapshot.
  if self._ignored_snapshot[fullpath] then
    self._ignored_cache[fullpath] = true
    return true
  end

  -- Lightweight "under known ignored dir" prefix check.
  if self._ignored_dir_prefixes then
    for _, prefix in ipairs(self._ignored_dir_prefixes) do
      if fullpath == prefix or vim.startswith(fullpath, prefix .. "/") then
        self._ignored_cache[fullpath] = true
        return true
      end
    end
  end

  -- Legacy per-path fallback (should rarely be reached now).
  -- Prefer any already-loaded Project from the centralized bsi.git.status (optimization #2 + #4).
  local git = require("bsi.git")
  if git.status and git.status._projects_by_toplevel then
    for _, proj in pairs(git.status._projects_by_toplevel) do
      if proj.path_ignored_in_project and proj:path_ignored_in_project(fullpath) then
        self._ignored_cache[fullpath] = true
        return true
      end
    end
  end

  if self._git_root == nil then
    local dir = vim.fn.isdirectory(fullpath) == 1 and fullpath or vim.fn.fnamemodify(fullpath, ":h")
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

  local under_ignored = (opts and opts._under_ignored) or false
  local this_ignored = under_ignored or self:_is_git_ignored(path)

  local node = {
    id = path,
    name = vim.fn.fnamemodify(path, ":t") or path,
    path = path,
    type = depth == 0 and "root" or "directory",
    depth = depth,
    expanded = opts.expand_all or (depth == 0),
    children = {},
    git_status = node_gs,
    git_ignored = this_ignored,
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
      local child_ignored = this_ignored or self:_is_git_ignored(fullpath)
      local force_full = opts and opts._force_full_ignored_scan or false

      -- Bounded initial scan support: if caller set max_depth, do not descend beyond it
      -- for non-forced, non-expand_all cases. The dir will be a stub; toggle/find_file
      -- will populate on demand (existing lazy paths).
      local max_d = opts and opts.max_depth
      local at_max_depth = max_d and (depth + 1 > max_d)

      if not force_full and this_ignored and not opts.expand_all then
        -- Performance: for git-ignored directories, scan/render only one level deep.
        -- (Direct children of ignored dir are included; their sub-children are stubbed.)
        -- When the user toggles an ignored dir we force-list its direct children only;
        -- their subdirs remain shallow to keep render cost low even for huge trees
        -- (node_modules, vendor, dist, etc.). Deep expansion only on explicit toggle of subdirs.
        child = {
          id = fullpath,
          name = name,
          path = fullpath,
          type = "directory",
          depth = depth + 1,
          expanded = false,
          children = {},
          git_status = g_status ~= "dir" and g_status or nil,
          git_numstat = numstat,
          git_ignored = child_ignored,
          _shallow_ignored = true,
        }
      elseif at_max_depth and not force_full and not opts.expand_all then
        -- Bounded: represent as unpopulated (or shallow) stub dir. Will be filled
        -- when user opens it or find_file / navigate targets inside it.
        child = {
          id = fullpath,
          name = name,
          path = fullpath,
          type = "directory",
          depth = depth + 1,
          expanded = false,
          children = {},
          git_status = g_status ~= "dir" and g_status or nil,
          git_numstat = numstat,
          git_ignored = child_ignored,
          _unpopulated = true,
        }
      else
        local sub_opts = vim.tbl_extend("force", opts or {}, { _under_ignored = this_ignored or child_ignored })
        if force_full then
          -- Do not propagate force_full when we are inside an ignored directory.
          -- This lets the user open a gitignored dir (e.g. node_modules) and see
          -- its direct children (package dirs) without deeply scanning/rendering
          -- every subdir inside those packages. Subdirs of ignored stay shallow
          -- until the user explicitly toggles them.
          if not this_ignored then
            sub_opts._force_full_ignored_scan = true
          end
        end
        child = self:scan(fullpath, depth + 1, sub_opts)
        if child then
          if git_only and #child.children == 0 then goto continue end
          child.expanded = opts.expand_all or false
        else goto continue end
      end
    else
      local child_ignored = this_ignored or self:_is_git_ignored(fullpath)
      child = { id = fullpath, name = name, path = fullpath, type = "file", depth = depth + 1, expanded = false, children = nil, git_status = g_status ~= "dir" and g_status or nil, git_numstat = numstat, git_ignored = child_ignored }
      -- Precompute icon for files at scan time (used on every rerender for display).
      -- Moves the devicons lookup cost out of the hot render path.
      if has_devicons then
        local ic, hl = devicons.get_icon(name, vim.fn.fnamemodify(name, ":e"), { default = true })
        child._icon = ic
        child._icon_hl = hl
      else
        child._icon = ""
      end
    end
    table.insert(node.children, child)
    ::continue::
  end

  if this_ignored and not (opts and opts._force_full_ignored_scan) then
    node._shallow_ignored = true
  end
  -- When force_full was used to open an ignored dir, we still allow the normal
  -- this_ignored shallow mark to apply to *its children* (because propagation of
  -- force_full is suppressed under ignored). This keeps subdir renders minimal.

  if git_changes and node.type == "directory" and not node.git_ignored then
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
  if git_changes and node.type == "directory" and node.children and not node.git_ignored then
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
    if node.git_ignored or child.git_ignored then
      -- don't collapse chains under ignored dirs, so the ignored dir name remains as a distinct
      -- toggle point for user to "open" and trigger full inner render
    else
      node.name = node.name .. "/" .. child.name
      node.children = child.children
      node.path = child.path
      node.id = child.id
      node.git_status = child.git_status
      node.git_status_summary = child.git_status_summary
      node.git_ignored = child.git_ignored
      node._shallow_ignored = child._shallow_ignored
      local function sync_depth(n, d)
        n.depth = d
        if n.children then for _, c in ipairs(n.children) do sync_depth(c, d + 1) end end
      end
      if node.children then for _, c in ipairs(node.children) do sync_depth(c, node.depth + 1) end end
    end
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

  -- Fast synchronous filesystem scan for instant directory listing.
  -- Git state (status, ignored files, numstat, decorations) is calculated in the
  -- background via async fetches and applied when ready (may trigger re-scan + re-render).
  -- This makes the basic tree appear immediately even if git commands are slow.
  self._git_changes = nil
  self._git_numstats = nil
  self.provider._ignored_snapshot = nil
  self.provider._ignored_dir_prefixes = nil
  self._git_fetch_pending = 0
  self._git_fetch_started = false
  self._refreshing = false

  -- Bounded initial scan for performance: only populate direct children of root by default.
  -- Deeper directories are created as stubs (_unpopulated=true or _shallow_ignored).
  -- toggle(), find_file(), and expand paths populate on demand.
  -- Only use full depth for explicit expand_all.
  local initial_max_depth = opts.expand_all and nil or 1

  self._initial_scan_opts = {
    expand_all = opts.expand_all,
    git_only = false,
    show_ignored = self.show_ignored,
    max_depth = initial_max_depth,
  }

  -- Quick *synchronous* fs directory read (provider:scan) for instant visible tree.
  -- Cheap name-based filters (DEFAULT_IGNORE + unconditional .git) only.
  -- Dotfiles are always included. Full git state (ignored pruning, etc.) is calculated
  -- asynchronously in the background fetches; when ready we re-scan with the data
  -- and re-render. This matches the request: directory listing fast+sync, git in bg.
  local quick_opts = vim.tbl_extend("force", self._initial_scan_opts, {
    git_changes = nil,
    git_numstats = nil,
  })
  local quick_root = self.provider:scan(self.root_path, 0, quick_opts)
  self.state = {
    root = quick_root or {
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

  -- Kick off async git data collection in background. When ready,
  -- _complete_initial_scan will (re)build with full git info.
  self:_start_async_git_fetch()

  -- For git_only views we still want the "auto expand changed" behavior once data is ready
  -- (handled inside _complete_initial_scan).
  if opts.git_only then
    self.opts.git_only = true
  end

  self.bufnr = opts.bufnr
  self.winid = opts.winid
  return self
end

--- Kick off the async git data fetches (changes + numstats + ignored snapshot/Project).
--- The snapshot is always fetched so filtering in scan() is accurate and cheap.
--- show_ignored only decides whether gitignored nodes are created or omitted (shown gray).
--- Dotfiles are always added regardless of this flag.
--- Uses bsi.cmd (vim.system) + the bsi.git.status runner for the ignored part.
function Tree:_start_async_git_fetch()
  if self._git_fetch_started then return end
  self._git_fetch_started = true

  -- Always collect the full git data (changes + numstats + ignored snapshot via the
  -- optimized bsi.git.status runner + Project). This is required for correct, cheap
  -- gitignore filtering during the fs_scandir loop (optimization #1 + #2 + #4).
  -- The `show_ignored` flag only controls *application* of the git_ignored filter:
  --   false (default) = skip creation of gitignored nodes (hide them)
  --   true  = create them (but marked git_ignored for gray rendering + shallow population)
  -- Dotfiles are always created (never filtered by show_ignored).
  -- The expensive per-path check-ignore is avoided; we use one-shot snapshot + prefix + parent propagation.
  self._git_fetch_pending = 3

  local function on_done_one()
    self._git_fetch_pending = self._git_fetch_pending - 1
    if self._git_fetch_pending <= 0 then
      self:_complete_initial_scan()
    end
  end

  self:_fetch_git_changes_async(on_done_one)
  self:_fetch_git_numstats_async(on_done_one)
  self:_fetch_git_ignored_snapshot_async(on_done_one)
end

--- Async fetch for porcelain git status (including untracked dir expansion).
--- Mirrors the old _get_git_changes logic but non-blocking.
function Tree:_fetch_git_changes_async(done)
  local req_root = self.root_path

  -- First rev-parse to get the true toplevel (needed for correct status and filtering)
  Cmd.new({ "git", "-C", req_root, "rev-parse", "--show-toplevel" }, {
    on_success = function(c)
      local git_root = vim.trim(c:job().stdout or "")
      if git_root == "" then
        self._git_changes = nil
        done()
        return
      end
      git_root = vim.fn.fnamemodify(git_root, ":p"):gsub("/$", "")
      git_root = vim.fn.resolve(git_root):gsub("/$", "")
      self._git_toplevel = git_root

      -- Opportunistic reuse of the Project (seeded by the always-on ignored snapshot fetch).
      -- The runner command we use for ignored already gives a full XY map (including ??, M , etc.).
      -- This avoids a duplicate `git status` process (saves real time on large repos).
      -- We still run the untracked-dir expansion for ?? dirs (needed for git_only + injection).
      local git = require("bsi.git")
      local proj = git.status and git.status._projects_by_toplevel and git.status._projects_by_toplevel[git_root]
      if proj and proj.files and next(proj.files) then
        local changes = {}
        changes[git_root] = { status = "dir" }

        local function under_req(p)
          return p == req_root or p:sub(1, #req_root + 1) == req_root .. "/"
        end

        for full, xy in pairs(proj.files) do
          if xy ~= "!!" then
            if under_req(full) then
              changes[full] = { status = xy }
              local current = full
              while #current > #git_root do
                current = vim.fn.fnamemodify(current, ":h")
                if not changes[current] then
                  changes[current] = { status = "dir" }
                elseif changes[current].status ~= "dir" then
                  break
                end
                if current == git_root then break end
              end
            end
          end
        end

        -- Replicate the ?? untracked dir full expansion (list every file inside)
        for fullpath, info in pairs(changes) do
          if info.status == "??" and vim.fn.isdirectory(fullpath) == 1 then
            local function mark_untracked(p)
              if under_req(p) then changes[p] = { status = "??" } end
              local h = vim.loop.fs_scandir(p)
              if h then
                while true do
                  local name, typ = vim.loop.fs_scandir_next(h)
                  if not name then break end
                  local fp = p .. "/" .. name
                  if typ == "directory" then
                    mark_untracked(fp)
                  else
                    if under_req(fp) then changes[fp] = { status = "??" } end
                  end
                end
              end
            end
            mark_untracked(fullpath)
          end
        end

        self._git_changes = changes
        done()
        return
      end

      -- Fallback (no Project yet, or race): run the status ourselves (with no-optional-locks).
      -- The new GitRunner can be unified further in a later pass to have a single status call feed both.
      Cmd.new({ "git", "--no-optional-locks", "-C", git_root, "status", "--porcelain" }, {
        on_success = function(c2)
          local result = c2:job().stdout or ""
          if result == "" then
            self._git_changes = nil
            done()
            return
          end

          local changes = {}
          changes[git_root] = { status = "dir" }

          local function under_req(p)
            return p == req_root or p:sub(1, #req_root + 1) == req_root .. "/"
          end

          for line in result:gmatch("[^\r\n]+") do
            local status = line:sub(1, 2)
            local path = line:sub(4)
            if path:match('^"') then path = path:match('^"(.*)"$') end
            if path:match(" %-> ") then path = vim.split(path, " -> ")[2] end

            local fullpath = (git_root .. "/" .. path):gsub("/$", "")

            if status == "??" and vim.fn.isdirectory(fullpath) == 1 then
              local function mark_untracked(p)
                if under_req(p) then
                  changes[p] = { status = "??" }
                end
                local h = vim.loop.fs_scandir(p)
                if h then
                  while true do
                    local name, typ = vim.loop.fs_scandir_next(h)
                    if not name then break end
                    local fp = p .. "/" .. name
                    if typ == "directory" then
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
                  if not changes[current] then
                    changes[current] = { status = "dir" }
                  elseif changes[current].status ~= "dir" then
                    break
                  end
                  if current == git_root then break end
                end
              end
            end
          end

          self._git_changes = changes
          done()
        end,
        on_error = function()
          self._git_changes = nil
          done()
        end,
      })
    end,
    on_error = function()
      self._git_changes = nil
      done()
    end,
  })
end

--- Async fetch for git numstat (+/- deltas).
function Tree:_fetch_git_numstats_async(done)
  local root = self.root_path

  local cached = self._git_toplevel
  if cached and cached ~= "" then
    -- Fast path: reuse toplevel discovered elsewhere (changes or ignored fetch)
    local git_root = cached
    local stats = {}

    local function parse_and_merge(output)
      for line in output:gmatch("[^\r\n]+") do
        local added_str, deleted_str, path = line:match("^(%S+)%s+(%S+)%s+(.+)$")
        if not added_str or not deleted_str or not path then goto continue end

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

    local pending = 2
    local function maybe_done()
      pending = pending - 1
      if pending == 0 then
        self._git_numstats = next(stats) and stats or nil
        done()
      end
    end

    Cmd.new({ "git", "-C", git_root, "diff", "--numstat" }, {
      on_success = function(c1)
        parse_and_merge(c1:job().stdout or "")
        maybe_done()
      end,
      on_error = function() maybe_done() end,
    })

    Cmd.new({ "git", "-C", git_root, "diff", "--cached", "--numstat" }, {
      on_success = function(c2)
        parse_and_merge(c2:job().stdout or "")
        maybe_done()
      end,
      on_error = function() maybe_done() end,
    })
    return
  end

  -- Fallback: discover toplevel ourselves
  Cmd.new({ "git", "-C", root, "rev-parse", "--show-toplevel" }, {
    on_success = function(c)
      local git_root = vim.trim(c:job().stdout or "")
      if git_root == "" then
        self._git_numstats = nil
        done()
        return
      end
      self._git_toplevel = vim.trim(git_root)

      local stats = {}

      local function parse_and_merge(output)
        for line in output:gmatch("[^\r\n]+") do
          local added_str, deleted_str, path = line:match("^(%S+)%s+(%S+)%s+(.+)$")
          if not added_str or not deleted_str or not path then goto continue end

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

      local pending = 2
      local function maybe_done()
        pending = pending - 1
        if pending == 0 then
          self._git_numstats = next(stats) and stats or nil
          done()
        end
      end

      Cmd.new({ "git", "-C", self._git_toplevel, "diff", "--numstat" }, {
        on_success = function(c1)
          parse_and_merge(c1:job().stdout or "")
          maybe_done()
        end,
        on_error = function() maybe_done() end,
      })

      Cmd.new({ "git", "-C", self._git_toplevel, "diff", "--cached", "--numstat" }, {
        on_success = function(c2)
          parse_and_merge(c2:job().stdout or "")
          maybe_done()
        end,
        on_error = function() maybe_done() end,
      })
    end,
    on_error = function()
      self._git_numstats = nil
      done()
    end,
  })
end

--- Async fetch for the gitignored snapshot / full Project (the key perf piece).
--- Always performed (decoupled from show_ignored) so the scandir filter in _should_skip
--- and parent_ignored propagation have the snapshot + prefix checks for O(1) decisions.
--- Delegates to bsi.git.status GitRunner (correct flags, parser, timeout guard, Project cache).
function Tree:_fetch_git_ignored_snapshot_async(done)
  local req_root = self.root_path

  local git = require("bsi.git")

  -- Fast path: if we already have a Project for this root, reuse its files map.
  local proj = git.load_project(req_root)
  if proj and proj.files and next(proj.files) then
    local ignored = {}
    local prefixes = {}
    for p, xy in pairs(proj.files) do
      if xy == "!!" then
        ignored[p] = true
        if vim.fn.isdirectory(p) == 1 then
          table.insert(prefixes, p)
        end
      end
    end
    self.provider._ignored_snapshot = ignored
    self.provider._ignored_dir_prefixes = next(prefixes) and prefixes or nil
    done()
    return
  end

  -- Otherwise do a fresh async collection via the new runner (also seeds the Project cache).
  git.run_git_status_async(req_root, nil, {
    -- timeout handled inside the runner
  }, function(map, err)
    if not map then
      self.provider._ignored_snapshot = {}
      self.provider._ignored_dir_prefixes = nil
      done()
      return
    end

    -- Seed a Project so future loads (and watchers) are fast.
    -- We don't call load_project again because the runner already produced the data.
    local toplevel = git.get_toplevel(req_root) or req_root
    self._git_toplevel = toplevel
    local Project = git.status.Project
    local fresh = Project.new(toplevel)
    fresh.files = map
    fresh._ignored_dir_prefixes = {}
    for p, xy in pairs(map) do
      if xy == "!!" and vim.fn.isdirectory(p) == 1 then
        table.insert(fresh._ignored_dir_prefixes, p)
      end
    end
    fresh:_build_dirs()
    git.status._projects_by_toplevel[toplevel] = fresh

    -- Start the narrow .git watcher for this project (if not already).
    if not fresh.watcher then
      fresh:start_watcher(function() end)
    end

    local ignored = {}
    local prefixes = {}
    for p, xy in pairs(map) do
      if xy == "!!" then
        ignored[p] = true
        if vim.fn.isdirectory(p) == 1 then
          table.insert(prefixes, p)
        end
      end
    end

    self.provider._ignored_snapshot = ignored
    self.provider._ignored_dir_prefixes = next(prefixes) and prefixes or nil
    done()
  end)
end

--- Called when all async git data has arrived (from either initial construction or a refresh).
--- Re-scans the tree with git data now available (changes, numstats, ignored snapshot).
--- This is the "background" step that adds git status, ignored filtering, decorations etc.
--- The fast sync fs scan already happened in new() for instant UI.
--- If a refresh restore was pending, it performs the expansion preservation logic.
function Tree:_complete_initial_scan()
  local is_refresh = self._pending_refresh_restore ~= nil
  local restore_info = self._pending_refresh_restore
  local was_refresh = is_refresh
  self._pending_refresh_restore = nil

  local new_root = nil

  if is_refresh then
    -- Refresh path still needs a real FS re-scan to pick up structural changes + restore expansion.
    local effective_max_depth = nil
    local scan_opts = vim.tbl_extend("force", self._initial_scan_opts or {
      expand_all = false,
      git_only = false,
      show_ignored = self.show_ignored,
    }, {
      git_changes = self._git_changes,
      git_numstats = self._git_numstats,
      show_ignored = self.show_ignored,
      max_depth = effective_max_depth,
    })

    new_root = self.provider:scan(self.root_path, 0, scan_opts)
    new_root = new_root or {
      id = self.root_path,
      name = vim.fn.fnamemodify(self.root_path, ":t"),
      path = self.root_path,
      type = "root",
      depth = 0,
      expanded = true,
      children = {},
    }
  end

  if is_refresh and restore_info then
    -- Restore expansion state (same logic as the old sync refresh)
    local function restore(node)
      if restore_info.expanded[node.id] or restore_info.expand_all then
        node.expanded = true
        if node.children then
          for _, child in ipairs(node.children) do restore(child) end
        end
      end
    end
    restore(new_root)

    -- After marking expanded, populate children for any restored dirs that are still stubs
    -- (important now that initial scans are bounded/shallow).
    local function populate_expanded(node)
      if (node.type == "directory" or node.type == "root") and node.expanded then
        local needs = (not node.children or #node.children == 0) or node._unpopulated or node._shallow_ignored
        if needs then
          local so = {
            git_changes = self._git_changes,
            git_numstats = self._git_numstats,
            show_ignored = self.show_ignored,
          }
          if node.git_ignored or node._shallow_ignored then
            so._force_full_ignored_scan = true
          end
          local sc = self.provider:scan(node.path, node.depth, so)
          if sc and sc.children then
            node.children = sc.children
          end
          node._shallow_ignored = false
          node._unpopulated = false
        end
      end
      if node.children then
        for _, child in ipairs(node.children) do populate_expanded(child) end
      end
    end
    populate_expanded(new_root)

    if next(restore_info.full_ignored_paths or {}) then
      local function restore_full_ignored(node)
        if restore_info.full_ignored_paths[node.id] and node.git_ignored then
          local so = {
            git_changes = self._git_changes,
            git_numstats = self._git_numstats,
            show_ignored = self.show_ignored,
            _force_full_ignored_scan = true,
          }
          local sc = self.provider:scan(node.path, node.depth, so)
          if sc and sc.children then
            node.children = sc.children
          end
          node._shallow_ignored = false
          node._unpopulated = false
        end
        if node.children then
          for _, child in ipairs(node.children) do restore_full_ignored(child) end
        end
      end
      restore_full_ignored(new_root)
    end

    self.state.root = new_root
    self._visible_dirty = true

    if self.opts and self.opts.git_only then
      self:_expand_changed_dirs()
    end

    if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
      self:render()
    end

    self._refreshing = false
    self:_update_winbar()
    return
  end

  -- Normal initial completion path
  -- Prefer in-place decoration (no FS re-scan) for the quick shallow tree we already built.
  -- This is the key perf win: git data is attached + summaries recomputed + pruning applied.
  if self.state and self.state.root then
    self:_apply_git_data_to_current_tree()
  else
    -- Fallback (should be rare): build a minimal root if we somehow have no prior state
    self.state = {
      root = {
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
    self:_apply_git_data_to_current_tree()
  end

  if self.opts and self.opts.git_only then
    self:_expand_changed_dirs()
  end

  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    self:render()
    self:_update_winbar()
  end

  -- Seed from the currently opened file so the tree selection is on it.
  -- find_file will expand ancestor chain on demand (on-demand scans receive the git data we just attached).
  local opened_path = M.get_opened_file()
  if opened_path ~= "" then
    self:find_file(opened_path)
  end

  if was_refresh then
    self._refreshing = false
    self:_update_winbar()
  end
end

--- Returns the root path of the tree formatted for display (home-relative)
---@return string
function Tree:get_root_path() return vim.fn.fnamemodify(self.root_path, ":~") end

--- Flattens the tree structure into a list of nodes that are currently visible (based on expansion state)
---@return bsi.Node[]
function Tree:get_visible_nodes()
  -- Use cached list if no structural mutation since last build.
  -- git_only is a pure filter (no expansion change), so we still re-walk when it flips
  -- (toggle_git_mode sets dirty), but repeated renders after a cursor move or minor
  -- are free (no walk, no line rebuild).
  if self._visible_nodes and not self._visible_dirty then
    return self._visible_nodes
  end
  local nodes = {}
  local git_only = self.opts and self.opts.git_only
  local function walk(node)
    if node.type ~= "root" then
      if not git_only or self:_node_has_git_activity(node) then
        table.insert(nodes, node)
      end
    end
    if (node.type == "directory" or node.type == "root") and node.expanded and node.children then
      for _, child in ipairs(node.children) do walk(child) end
    end
  end
  walk(self.state.root)
  self._visible_nodes = nodes
  self._visible_dirty = false
  return nodes
end

--- Returns true if the node participates in git changes (has status or summary or numstat delta).
function Tree:_node_has_git_activity(node)
  if not node then return false end
  if node.git_status and node.git_status ~= "dir" then return true end
  if node.git_status_summary and node.git_status_summary ~= "" then return true end
  if node.git_numstat then
    local a = node.git_numstat.added or 0
    local d = node.git_numstat.deleted or 0
    if a + d > 0 then return true end
  end
  return false
end

--- Apply git data (changes, numstats, ignored snapshot) to the *existing* node tree.
--- No new filesystem scan. Used after async git data arrives to avoid redundant full scans.
--- Also recomputes directory git summaries. Prunes git-ignored nodes when show_ignored=false.
--- Dotfiles are never pruned (they are always present in the tree).
function Tree:_apply_git_data_to_current_tree()
  if not self.state or not self.state.root then return end
  local changes = self._git_changes or {}
  local numstats = self._git_numstats or {}
  local ignored = self.provider._ignored_snapshot or {}
  local ignored_prefixes = self.provider._ignored_dir_prefixes or {}
  local show_ignored = self.show_ignored

  local function is_ignored_path(p)
    if ignored[p] then return true end
    for _, pref in ipairs(ignored_prefixes) do
      if p == pref or vim.startswith(p, pref .. "/") then return true end
    end
    return false
  end

  -- Bottom-up decoration + summary recompute
  local function decorate(node, parent_ignored)
    local p = node.path

    -- numstat
    local ns = numstats[p]
    if ns and (ns.added or 0) + (ns.deleted or 0) > 0 then
      node.git_numstat = ns
    else
      node.git_numstat = nil
    end

    -- raw status (files and dirs)
    local ch = changes[p]
    if ch and ch.status and ch.status ~= "dir" then
      node.git_status = ch.status
    end

    -- ignored state (parent propagation + snapshot)
    local this_ignored = parent_ignored or is_ignored_path(p)
    node.git_ignored = this_ignored

    if node.type == "directory" or node.type == "root" then
      if node.children then
        for _, c in ipairs(node.children) do
          decorate(c, this_ignored)
        end
      end

      -- Recompute DIR_* status and canonical summary (A/M/D) from children
      -- (same rules as the original scan logic)
      if changes and next(changes) and not node.git_ignored then
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

        local dir_gs = nil
        if all_untracked and some_unstaged then dir_gs = "DIR_UNTRACKED"
        elseif all_staged and some_staged then dir_gs = "DIR_ADDED"
        elseif some_staged or some_unstaged then
          local statuses, chars = {}, {}
          local function add_status(s)
            if not s then return end
            if s == "DIR_ADDED" then s = "A"
            elseif s == "DIR_PARTIAL" then s = "M"
            elseif s == "DIR_UNTRACKED" then s = "?"
            end
            for j = 1, #s do
              local ch = s:sub(j, j)
              if ch ~= " " and not statuses[ch] then
                statuses[ch] = true
                table.insert(chars, ch)
              end
            end
          end
          for _, c in ipairs(node.children) do add_status(c.git_status) end
          table.sort(chars)
          if #chars > 0 then dir_gs = "DIR_MULTI:" .. table.concat(chars, "") end
        end
        node.git_status = dir_gs

        -- Canonical [DMA] summary
        local has = { A = false, M = false, D = false }
        local function mark(s)
          if not s then return end
          if s == "DIR_ADDED" or s == "DIR_UNTRACKED" then has.A = true; return end
          if s == "DIR_PARTIAL" then has.A = true; has.M = true; return end
          if type(s) == "string" and s:sub(1, 10) == "DIR_MULTI:" then
            local rest = s:sub(11)
            if rest:match("A") or rest:match("%?") then has.A = true end
            if rest:match("[MRC]") then has.M = true end
            if rest:match("D") then has.D = true end
            return
          end
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
        node.git_status_summary = (#summary > 0) and summary or nil
      end
    end
  end

  decorate(self.state.root, false)

  -- When not showing ignored, prune subtrees that are now known to be git-ignored.
  -- This keeps the shallow tree correct after snapshot arrives.
  if not show_ignored then
    local function prune_ignored(node)
      if not node.children then return end
      local kept = {}
      for _, c in ipairs(node.children) do
        if c.git_ignored then
          -- drop the whole subtree from visible structure
        else
          prune_ignored(c)
          table.insert(kept, c)
        end
      end
      node.children = kept
    end
    prune_ignored(self.state.root)
  end

  self._visible_dirty = true
end


--- Updates the tree buffer by flattening the state and calling the renderer
function Tree:render()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then return end

  -- Lightweight throttle: many Buf* events and git callbacks can fire together.
  -- Structural changes set _visible_dirty=true so they always go through.
  local now = (vim.uv and vim.uv.now and vim.uv.now()) or 0
  if not self._visible_dirty and self._last_render_ms and (now - self._last_render_ms) < 60 then
    return
  end
  self._last_render_ms = now

  self.visible_nodes = self:get_visible_nodes()
  self.renderer:render(self.bufnr, self.visible_nodes, self.winid)
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

  -- Native cursorline + winhighlight gives us the BSITreeCursorLine background
  -- automatically on cursor moves inside this window with *zero* Lua/render cost.
  -- (Previously we re-ran full :render() on every CursorMoved just for this.)
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_set_option_value("cursorline", true, { win = self.winid })
    vim.api.nvim_set_option_value("winhighlight", "CursorLine:BSITreeCursorLine", { win = self.winid })
  end

  self:render()

  -- The initial render above shows the fast sync fs scan (quick tree).
  -- Git enhancements (statuses, ignored filtering, numstats) arrive later via
  -- background completion and will trigger another render.
  if self._git_fetch_pending and self._git_fetch_pending > 0 and self.winid and vim.api.nvim_win_is_valid(self.winid) then
    local base = self:get_root_path()
    if self.opts and self.opts.git_only then base = "Git: " .. base end
    local function render_title(t)
      vim.api.nvim_set_hl(0, "BSITreeTitle", { fg = "#3EFFDC", bold = true })
      return "%#BSITreeTitle# " .. t
    end
    vim.wo[self.winid].winbar = render_title(base .. " (loading...)")
  end

  -- Best-effort: ensure the single tracked opened file has its ancestor chain
  -- populated and selected.
  local opened = M.get_opened_file()
  if opened ~= "" then
    self:find_file(opened)
  end

  -- Set winbar (will be "Git: ..." if in git mode). The _complete path will also call this.
  self:_update_winbar()

  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = self.bufnr, silent = true, desc = "Tree: " .. desc })
  end

  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = self.bufnr,
    callback = function()
      M.instances[self.bufnr] = nil
      if M.the_tree and M.the_tree.bufnr == self.bufnr then
        M.the_tree = nil
      end
    end,
  })

  map("R", function() self:refresh() end, "Refresh")
  map("h", function() self:toggle_show_ignored() end, "Toggle git-ignored files/dirs (dotfiles are always shown)")
  map("q", "<cmd>close<cr>", "Close")
  map("<CR>", function() self:toggle() end, "Toggle / Expand directory")
  map("o", function() self:_open_system() end, "Open with system default app (Finder/Preview/etc)")
  map("d", function() self:_delete_node() end, "Delete file or directory (with confirmation)")
  map("D", function() self:_diff_file() end, "Diff file")
  map("g", function() self:toggle_git_mode() end, "Toggle git changes view (same buffer)")
  map("a", function() self:_add_file() end, "Add new file in current directory")
  map("r", function() self:rename_or_move() end, "Rename / Move file or directory")
  map("u", function() self:rename_or_move() end, "Rename / Move file or directory")
  map("y", function() self:_yank(false) end, "Yank name")
  map("Y", function() self:_yank(true) end, "Yank relative path")
  map("<LeftMouse>", "<LeftMouse>", "Select node")
  map("<2-LeftMouse>", function() self:toggle() end, "Open file / Toggle directory (double-click)")

  -- Standard Vim motions for top/bottom of the (visible) tree content.
  -- Matches default nvim behavior in normal buffers (gg = first line, G = last line).
  -- We explicitly set cursor on the win because visible_nodes map 1:1 to buffer lines.
  -- Pure cursor motions: just move the cursor.
  -- No re-render needed because the visible content and highlights haven't changed.
  -- (Native cursorline + BSITreeCursorLine winhighlight handles the visual "selection".)
  -- Compare to find_file/navigate_file which call render() because they can mutate
  -- the tree structure (lazy expansion) and therefore need to rebuild buffer lines.
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

--- Re-scans the filesystem and updates the tree state while attempting to preserve current expansion
function Tree:refresh()
  -- Capture expansion state *before* starting new collection.
  -- We deliberately keep the current tree data (nodes, expansions, old git decorations)
  -- visible while the fresh fs scan + git status + numstat are collected in the background.
  local expanded = {}
  local full_ignored_paths = {}
  local function collect(node)
    if node.expanded then expanded[node.id] = true end
    if node.git_ignored and not node._shallow_ignored then
      full_ignored_paths[node.id] = true
    end
    if node.children then for _, child in ipairs(node.children) do collect(child) end end
  end
  collect(self.state.root)

  -- Store restore info for when async data arrives
  self._pending_refresh_restore = {
    expanded = expanded,
    full_ignored_paths = full_ignored_paths,
    expand_all = self.opts and self.opts.expand_all,
  }

  -- Clear only per-collection scratch caches. Do *not* nuke the live tree state
  -- or the current git data maps — we want the user to continue seeing the tree
  -- (with its current structure and decorations) until the new data is ready.
  if self.provider then
    self.provider._ignored_cache = {}
    self.provider._git_root = nil
    self.provider._ignored_snapshot = nil
    self.provider._ignored_dir_prefixes = nil
  end
  -- Intentionally do *not* do:
  --   self._git_changes = nil
  --   self._git_numstats = nil
  --   self.state = { empty root }
  -- This is the "rerender without cleaning all data before we collect new" behavior.

  self._refreshing = true
  if self.winid and vim.api.nvim_win_is_valid(self.winid) then
    self:_update_winbar()
  end
  -- Do not render() here with placeholder content. The existing buffer lines stay.

  -- Kick off async collection. When all three finish, _complete_initial_scan
  -- will build the fresh root (full scan for refresh) + restore expansion and swap it in.
  self._git_fetch_started = false
  self._git_fetch_pending = 3
  self:_start_async_git_fetch()
end

--- Toggles visibility of git-ignored files and directories.
--- Dotfiles (e.g. .github/, .env*) are always shown.
--- The git data (snapshot/Project) is collected unconditionally for correct filtering.
--- This flag only changes whether gitignored paths are skipped at scan time or included (grayed, shallow).
function Tree:toggle_show_ignored()
  self.show_ignored = not (self.show_ignored or false)

  -- Clear per-provider caches so re-scan applies the new visibility/filter decision.
  -- The Project in bsi.git.status keeps the raw data and will be reused or refreshed.
  if self.provider then
    self.provider._ignored_cache = {}
    self.provider._git_root = nil
    self.provider._ignored_snapshot = nil
    self.provider._ignored_dir_prefixes = nil
  end

  self:refresh()
end

--- Updates the window title (winbar) to reflect current root and view mode (e.g. git).
function Tree:_update_winbar()
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then return end

  local title = self:get_root_path()
  if self.opts and self.opts.git_only then
    title = "Git: " .. title
  end
  if self._refreshing then
    title = title .. " (refreshing...)"
  end

  vim.api.nvim_set_hl(0, "BSITreeTitle", { fg = "#3EFFDC", bold = true })
  vim.wo[self.winid].winbar = "%#BSITreeTitle# " .. title
end

--- Toggles between full filesystem view and git-changes-only view (same buffer, like normal/insert mode).
-- This is fast: just flips the filter flag and re-renders visible nodes; no fs/git re-scan.
function Tree:toggle_git_mode()
  self.opts = self.opts or {}
  self.opts.git_only = not (self.opts.git_only or false)
  self._visible_dirty = true

  if self.opts.git_only then
    self:_expand_changed_dirs()
  end

  self:render()
  self:_update_winbar()

  -- After switching view mode (e.g. from git back to full/"ee" mode), try to
  -- position the tree's cursor/selection on the currently opened file, if it's
  -- visible in the new mode. This keeps the "focus" in the tree on the user's
  -- work file. find_file only sets cursor inside the tree win (no global focus change).
  local opened_path = M.get_opened_file()
  if opened_path ~= "" then
    self:find_file(opened_path)
  end
end

--- Internal: expand directories that have git changes (used for git mode UX).
function Tree:_expand_changed_dirs()
  local function expand_changed(node)
    local has_change = node.git_status
      or (node.git_status_summary and node.git_status_summary ~= "")
      or (node.git_numstat and ((node.git_numstat.added or 0) + (node.git_numstat.deleted or 0) > 0))
    if has_change and (node.type == "directory" or node.type == "root") then
      node.expanded = true
      if node.git_ignored and node._shallow_ignored then
        local so = {
          git_changes = self._git_changes,
          git_numstats = self._git_numstats,
          show_ignored = self.show_ignored,
          _force_full_ignored_scan = true,
        }
        local sc = self.provider:scan(node.path, node.depth, so)
        if sc and sc.children then
          node.children = sc.children
        end
        node._shallow_ignored = false
        node._unpopulated = false
        -- children of this ignored dir are loaded one level; their subdirs remain
        -- shallow (scan propagation prevents deep force under ignored).
      end
    end
    if node.children then
      for _, child in ipairs(node.children) do expand_changed(child) end
    end
  end
  expand_changed(self.state.root)
  self._visible_dirty = true
end

--- Toggles the expansion state of the directory under the cursor or opens the file
function Tree:toggle()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
  if not node or node.type == "file" then self:_open_file() return end
  if not node.expanded and node.type == "directory" then
    local needs_load = (node.children and #node.children == 0) or node._shallow_ignored or node.git_ignored or node._unpopulated
    if needs_load then
      local scan_opts = {
        git_changes = self._git_changes,
        git_numstats = self._git_numstats,
        show_ignored = self.show_ignored,
      }
      if node.git_ignored or node._shallow_ignored then
        scan_opts._force_full_ignored_scan = true
      end
      local scanned = self.provider:scan(node.path, node.depth, scan_opts)
      if scanned and scanned.children then
        node.children = scanned.children
        node._shallow_ignored = false
        node._unpopulated = false
      end
    end
  end
  -- For git_ignored nodes we load direct children above (one level), but do not
  -- force their subdirs open. This minimizes both scan depth and visible nodes
  -- during render for large ignored trees. Subdirs under them stay lazy/shallow.
  node.expanded = not node.expanded
  -- Note: we intentionally do NOT auto-expand descendants under git_ignored nodes.
  -- Even after force-loading direct children of an ignored dir, child directories
  -- start collapsed (or as shallow stubs). This keeps the visible node count and
  -- render cost minimal. User can drill into specific subdirs as needed.
  self._visible_dirty = true
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

--- Opens the node (file or directory) under the cursor using the system's default application
--- (e.g. Finder/Explorer for directories, default viewer for images/PDFs, browser for HTML, etc.)
function Tree:_open_system()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
  if not node then return end
  if system and system.open_url then
    system.open_url(node.path)
  else
    vim.notify("bsi.system not available for system open", vim.log.levels.WARN)
  end
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

--- Deletes the node (file or directory) under the cursor after confirmation.
--- Supports recursive delete for directories.
function Tree:_delete_node()
  if not self.visible_nodes or #self.visible_nodes == 0 then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local idx = cursor[1]
  local node = self.visible_nodes[idx]
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

    -- Clear tracking if this was the opened buffer
    if M.opened_buffer and vim.api.nvim_buf_get_name(M.opened_buffer) == path then
      M.opened_buffer = nil
    end

    -- Force close any buffer for this path
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end

    self:refresh()
  else
    vim.notify("Failed to delete " .. label .. ": " .. path, vim.log.levels.ERROR)
  end
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

  -- Fast path: if target is already in the current visible list (e.g. same dir area,
  -- or after prior expansion), just move cursor. No render needed.
  -- CurrentFile background highlight is driven by the real opened buffer (not tree cursor).
  -- Native cursorline provides selection. Avoids full re-render on every BufEnter sync.
  if self.visible_nodes then
    for i, node in ipairs(self.visible_nodes) do
      if node.path == target_path then
        if self.winid and vim.api.nvim_win_is_valid(self.winid) then
          pcall(vim.api.nvim_win_set_cursor, self.winid, { i, 0 })
        end
        -- No render() needed: this is a pure cursor move inside already-visible nodes.
        -- CurrentFile highlight is based on the actual opened buffer, not tree cursor.
        -- Native cursorline handles visual selection.
        return
      end
    end
  end

  local function expand_recursive(node, target)
    if node.path == target then return true end
    if node.type == "directory" or node.type == "root" then
      if target:sub(1, #node.path) == node.path then
        if not node.expanded then
          if (node.children and #node.children == 0) or node._unpopulated then
            local scan_opts = {
              git_changes = self._git_changes,
              git_numstats = self._git_numstats,
              show_ignored = self.show_ignored,
            }
            if node.git_ignored or node._shallow_ignored then
              scan_opts._force_full_ignored_scan = true
            end
            local scanned = self.provider:scan(node.path, node.depth, scan_opts)
            if scanned and scanned.children then
              node.children = scanned.children
              node._shallow_ignored = false
              node._unpopulated = false
            end
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
      if not current.children or #current.children == 0 or current._unpopulated then
        -- lazy populate if somehow empty (defensive)
        local scan_opts = {
          git_changes = self._git_changes,
          git_numstats = self._git_numstats,
          show_ignored = self.show_ignored,
        }
        if current.git_ignored or current._shallow_ignored then
          scan_opts._force_full_ignored_scan = true
        end
        local scanned = self.provider:scan(current.path, current.depth, scan_opts)
        if scanned and scanned.children then
          current.children = scanned.children
          current._shallow_ignored = false
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
    -- Pure cursor move + file open. No need to re-render the tree content.
    -- Cursorline is native; re-rendering would be wasteful for a simple navigation.
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
-- Always targets M.the_tree (or adopts the first Tree found as the one).
function M.toggle_tree()
  -- Prefer the tracked one
  if M.the_tree and M.the_tree.winid and vim.api.nvim_win_is_valid(M.the_tree.winid) then
    vim.api.nvim_win_close(M.the_tree.winid, true)
    M.the_tree = nil
    return
  end

  -- Adopt or find any existing Tree window
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
    vim.api.nvim_win_close(found_win, true)
    M.the_tree = nil
    return
  end

  -- Open a fresh one and track it as the one
  local t = M.new()
  t:open()
  M.the_tree = t

  -- Position on the opened file (so the tree selection is on it), then return
  -- focus to the editing buffer.
  local opened_path = M.get_opened_file()
  if opened_path ~= "" then
    t:find_file(opened_path)
  end
  vim.cmd("wincmd l")
end

--- Ensures a BSI tree is visible and switched to git-changes mode (same buffer, like a view mode).
--- If no tree is open, opens one directly in git mode.
--- Always targets/sets M.the_tree so that <leader>ee and <leader>ge stay on the one buffer.
--- Mapped to <leader>ge.
function M.show_in_git_mode()
  -- If we have a tracked one, use it (switch mode if needed)
  if M.the_tree and M.the_tree.winid and vim.api.nvim_win_is_valid(M.the_tree.winid) then
    if not (M.the_tree.opts and M.the_tree.opts.git_only) then
      M.the_tree:toggle_git_mode()
    end
    -- Do not steal focus here: changing mode on an already-visible tree should
    -- keep the user's focus on the opened file buffer. The toggle_git_mode above
    -- already called find_file to position the tree's internal cursor/selection
    -- on the opened file (if possible in the target mode).
    return
  end

  -- Find any existing Tree window and adopt it as the one, then switch to git mode
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
      M.the_tree = t
      if not (t.opts and t.opts.git_only) then
        t:toggle_git_mode()
      end
      vim.api.nvim_set_current_win(found_win)
    end
    return
  end

  -- No tree at all: open fresh in git mode and track as the one
  local t = M.new({ git_only = true })
  t:open()
  M.the_tree = t

  -- Position the (git-mode) tree cursor on the opened file if it's visible
  -- in git view. Then wincmd l to return focus to the editing buffer / opened file.
  local opened_path = M.get_opened_file()
  if opened_path ~= "" then
    t:find_file(opened_path)
  end
  vim.cmd("wincmd l")
end

--- Set the single tracked "opened buffer" (the main editing buffer the user works with).
--- We only track normal file buffers (buftype=="", not Tree/GitView, has a name).
--- This is used by renders for "current file" highlight and by find_file syncing.
function M.set_opened_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  if vim.bo[bufnr].buftype ~= "" then return end
  local ft = vim.bo[bufnr].filetype
  if ft == "Tree" or ft == "GitView" then return end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then return end
  M.opened_buffer = bufnr
end

--- Get the currently tracked opened buffer (or nil if none/invalid).
function M.get_opened_buffer()
  local buf = M.opened_buffer
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  M.opened_buffer = nil
  return nil
end

--- Get the file path of the tracked opened buffer ("" if none).
function M.get_opened_file()
  local buf = M.get_opened_buffer()
  if buf then
    return vim.api.nvim_buf_get_name(buf) or ""
  end
  return ""
end

--- Initializes global tree settings, highlights, autocommands, and user commands
---@param opts table|nil Configuration options (e.g. { show_ignored = true })
function M.setup(opts)
  opts = opts or {}
  -- Merge user options into the global config
  for k, v in pairs(opts) do
    M.config[k] = v
  end

  -- Seed the tracked opened buffer from the current buffer at setup time.
  -- (User works only with one buffer; this becomes the authoritative "current file"
  -- for highlighting and find_file in all trees.)
  M.set_opened_buffer()

  vim.api.nvim_set_hl(0, "BSITreeCurrentFile", { bg = "#3b4261", bold = true })
  vim.api.nvim_set_hl(0, "BSITreeOpenedFile", { fg = "#7aa2f7", italic = true })
  vim.api.nvim_set_hl(0, "BSITreeCursorLine", { bg = "#2e3a4a" })  -- cursor line inside the tree (full line)

  -- Git change type colors for inline file detail (+N-M)
  -- bg = "NONE" prevents interference with the current-file background highlight
  vim.api.nvim_set_hl(0, "BSITreeGitAdded",    { fg = "#9ece6a", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeGitModified", { fg = "#e0af68", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeGitDeleted",  { fg = "#f7768e", bg = "NONE" })
  vim.api.nvim_set_hl(0, "BSITreeGitIgnored",  { fg = "#5c6370", bg = "NONE" })  -- grey for git-ignored files/dirs (shown when toggle 'h' / show_ignored)

  -- Commands for the git status integration (from the detailed implementation plan)
  vim.api.nvim_create_user_command("BSIGitEnable", function()
    local git = require("bsi.git")
    git.enable_git_integration()
    vim.notify("BSI Git integration re-enabled. Refresh any open trees (R) to pick up status again.", vim.log.levels.INFO)
  end, { desc = "Re-enable git status / gitignore tracking after degradation or manual disable" })

  vim.api.nvim_create_user_command("BSIGitDisable", function()
    local git = require("bsi.git")
    git.disable_git_integration("user command")
    vim.notify("BSI Git integration disabled. Use :BSIGitEnable to restore.", vim.log.levels.WARN)
  end, { desc = "Temporarily disable all git status / gitignore work (graceful degradation)" })

  vim.api.nvim_create_user_command("BSIGitStatus", function()
    local git = require("bsi.git")
    local status = git.status
    local msg = string.format(
      "Git integration: %s | consecutive timeouts: %d | projects cached: %d",
      status.is_git_integration_enabled() and "ENABLED" or ("DISABLED (" .. (status._last_disable_reason or "unknown") .. ")"),
      status._consecutive_timeouts or 0,
      vim.tbl_count(status._projects_by_toplevel or {})
    )
    vim.notify(msg, vim.log.levels.INFO)
  end, { desc = "Show current state of the bsi.git.status runner / project manager" })

  local group = vim.api.nvim_create_augroup("BSITreeTracking", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local buf = args.buf

      -- Track the opened buffer (the single main editing buffer).
      -- This is the authoritative "current file" for trees (avoids picking the tree
      -- itself or other splits when the user focuses the tree sidebar).
      M.set_opened_buffer(buf)

      -- When focusing the BSI Tree buffer itself: nothing to do for rendering.
      -- Highlights live in extmarks (survive focus). Cursor selection is native cursorline.
      -- We deliberately avoid re-rendering on every focus/CursorMoved (see comments in open()).
      -- User can press R if they want a full git/fs resync.

      local path = vim.api.nvim_buf_get_name(buf)
      -- Only consider real file buffers for opened-file sync (skip tree, help, quickfix, terminals, etc.)
      if path == "" or vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "Tree" then
        return
      end

      -- Only sync tree selection (find_file + render) when the opened file actually changed.
      -- With full depth root scan, this is now just cheap cursor positioning + current file highlight.
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
      -- Clean up tracked opened buffer if it was deleted/wiped
      if M.opened_buffer and not vim.api.nvim_buf_is_valid(M.opened_buffer) then
        M.opened_buffer = nil
      end
      for _, tree in pairs(M.instances) do tree:render() end
    end,
  })

  vim.api.nvim_create_user_command("BSITree", function(args)
    local root = args.args ~= "" and args.args or nil
    M.new({ root = root }):open()
  end, { nargs = "?", complete = "dir" })
end

return M
