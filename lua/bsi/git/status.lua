-- lua/bsi/git/status.lua
-- Clean, standalone Git Status Runner + Project manager for file tree explorers.
-- Follows the detailed architecture from the "Gitignore Detection, Status Tracking,
-- and Filtering from Scratch" plan.
--
-- Primary goals:
--   * Correctly identify every git-ignored path using a single reliable `git status` invocation.
--   * Provide full XY porcelain status for rendering (??, M , A , R , !!, etc.).
--   * Support fast ancestor queries via aggregated ProjectDirs.
--   * React to .git changes via watchers (Phase 6).
--   * Graceful degradation (no git, timeouts, disable_for_dirs, non-repo dirs).
--
-- This module is intentionally decoupled from any specific Tree implementation so it
-- can be shared or used by other consumers (git-only views, pickers, etc.).

local M = {}

-- ---------------------------------------------------------------------------
-- Constants & Global State (cross-cutting concerns)
-- ---------------------------------------------------------------------------

local DEFAULT_TIMEOUT = 8000 -- ms
local MAX_CONSECUTIVE_TIMEOUTS = 5

-- Global degradation state
M._git_disabled = false
M._consecutive_timeouts = 0
M._last_disable_reason = nil

-- Caches (as specified in plan section 3)
-- _toplevels_by_path[path] = toplevel | false   (false = "definitely not a git repo")
M._toplevels_by_path = {}
-- _projects_by_toplevel[toplevel] = Project
M._projects_by_toplevel = {}

-- Per-toplevel "show untracked" cache (git config status.showUntrackedFiles)
M._show_untracked_cache = {}

-- Critical .git files worth watching (optimization #5 from nvim-tree analysis).
-- Watching only these + using debounce + ignore_dirs on the FS watcher side
-- prevents the explosion of events from the rest of .git (objects, refs, logs, etc.).
local WATCHED_GIT_FILES = {
  "HEAD",
  "HEAD.lock",
  "FETCH_HEAD",
  "index",
  "config",
}

-- ---------------------------------------------------------------------------
-- Low-level utilities
-- ---------------------------------------------------------------------------

local function is_windows()
  return vim.loop.os_uname().sysname:find("Windows", 1, true) ~= nil
end

local function normalize_path(p)
  if not p then return p end
  p = vim.fn.fnamemodify(p, ":p")
  p = vim.fn.resolve(p)
  p = p:gsub("/+$", "")
  if is_windows() then
    p = p:gsub("\\", "/")
  end
  return p
end

local function join_path(a, b)
  a = a:gsub("/+$", "")
  b = b:gsub("^/+", "")
  return a .. "/" .. b
end

--- Kill a vim.System handle safely.
local function kill_handle(handle)
  if not handle then return end
  pcall(function()
    if handle and handle.pid then
      handle:kill(9)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- GitRunner: thin reliable wrapper (Phase 1 core deliverable)
-- ---------------------------------------------------------------------------

---@class GitRunner
local GitRunner = {}
M.GitRunner = GitRunner

---The single most important command per the plan.
---We always request untracked (-u) because --ignored=matching only produces "!!" entries
---when untracked files are also being reported.
GitRunner.BASE_CMD = {
  "git", "--no-optional-locks",
  "status", "--porcelain=v1", "-z",
  "--ignored=matching", "-u"
}

--- Parse raw stdout (NUL-separated) from the porcelain=v1 -z command into { [abs_path] = "XY", ... }
--- Correctly handles rename/copy records which emit an extra path field.
--- This is a small state machine over the NUL fields as described in the plan.
---@param stdout string
---@param git_root string
---@return table<string, string>  abs_path -> XY
function GitRunner.parse_porcelain_v1_z(stdout, git_root)
  local out = {}
  if not stdout or stdout == "" then return out end

  local entries = {}
  for entry in vim.gsplit(stdout, "\0", { plain = true, trimempty = false }) do
    table.insert(entries, entry)
  end

  local function looks_like_status(tok)
    if not tok or tok == "" then return false end
    -- Common two-char porcelain statuses (including "R " "C " "!!" "??" etc.)
    -- Also tolerate "R100" style or "R  " (with score or extra space) that git may emit for renames.
    if #tok >= 2 and tok:sub(1,1):match('[ MADRCU?!]') and tok:sub(2,2):match('[ MADRCU?!]') then
      return true
    end
    if tok:match('^R[0-9]') or tok:match('^C[0-9]') then
      return true
    end
    return false
  end

  local i = 1
  while i <= #entries do
    local tok = entries[i]
    if tok == "" or not looks_like_status(tok) then
      i = i + 1
    else
      -- tok is a status indicator (e.g. "M ", "!!", "R  ", "R100", ...)
      local status = tok:sub(1, 2)
      if status == "" then
        status = tok:sub(1, 1) .. " "
      end

      -- Next field is (normally) the path associated with this status.
      i = i + 1
      local p1 = entries[i] or ""
      if p1 ~= "" then
        local rel = p1:gsub("^%s+", "")
        if rel ~= "" then
          local abs = join_path(git_root, rel)
          abs = normalize_path(abs)
          out[abs] = status
        end
      else
        -- empty path after status token; just advance
      end

      -- For renames/copies there is one extra path field (origin or the other side).
      -- We already stored the status under the primary path (p1). Skip the second path.
      if status:sub(1,1) == "R" or status:sub(1,1) == "C" or tok:match('^R[0-9]') or tok:match('^C[0-9]') then
        i = i + 1
      end

      i = i + 1
    end
  end

  return out
end

--- Run the git status synchronously (small trees / initial load fallback).
--- Returns map of absolute path -> XY or nil on failure.
---@param toplevel string
---@param path? string   optional sub-path to limit (git status <path>)
---@param opts? table    { timeout?: number }
---@return table<string,string>|nil
function GitRunner.run(toplevel, path, opts)
  opts = opts or {}
  if M._git_disabled then return nil end

  toplevel = normalize_path(toplevel)
  local timeout = opts.timeout or DEFAULT_TIMEOUT

  local cmd = vim.deepcopy(GitRunner.BASE_CMD)
  if path then
    table.insert(cmd, path)
  end

  local out = vim.system(cmd, {
    cwd = toplevel,
    text = true,
    timeout = timeout,
  }):wait()

  if not out or out.code ~= 0 then
    GitRunner._record_failure("sync non-zero or no output")
    return nil
  end

  local map = GitRunner.parse_porcelain_v1_z(out.stdout or "", toplevel)
  GitRunner._record_success()
  return map
end

--- Run asynchronously. Calls done(map|nil, err_msg?) when finished or timed out.
---@param toplevel string
---@param path? string
---@param opts? table { timeout?: number, on_timeout?: fun() }
---@param done fun(map: table<string,string>|nil, err: string|nil)
function GitRunner.run_async(toplevel, path, opts, done)
  opts = opts or {}
  if M._git_disabled then
    vim.schedule(function() done(nil, "git integration disabled") end)
    return
  end

  toplevel = normalize_path(toplevel)
  local timeout_ms = opts.timeout or DEFAULT_TIMEOUT

  local cmd = vim.deepcopy(GitRunner.BASE_CMD)
  if path then table.insert(cmd, path) end

  local handle
  local timer
  local finished = false

  local function finish(map, err)
    if finished then return end
    finished = true
    if timer then timer:stop(); timer:close(); timer = nil end
    if handle then
      -- leave handle for GC; we already killed on timeout
    end
    vim.schedule(function() done(map, err) end)
  end

  -- Start the process
  local ok, sys_handle_or_err = pcall(vim.system, cmd, {
    cwd = toplevel,
    text = true,
    stdout = false,
    stderr = false,
  }, function(obj)
    if finished then return end
    if obj.code == 0 then
      local map = GitRunner.parse_porcelain_v1_z(obj.stdout or "", toplevel)
      GitRunner._record_success()
      finish(map)
    else
      GitRunner._record_failure("async non-zero exit: " .. tostring(obj.code))
      finish(nil, "git status failed: " .. tostring(obj.code))
    end
  end)

  if not ok then
    GitRunner._record_failure("vim.system failed to spawn: " .. tostring(sys_handle_or_err))
    finish(nil, "spawn failed")
    return
  end

  handle = sys_handle_or_err

  -- Timeout watchdog
  timer = vim.uv.new_timer()
  timer:start(timeout_ms, 0, function()
    if finished then return end
    finished = true
    kill_handle(handle)
    GitRunner._record_timeout(opts.on_timeout)
    finish(nil, "timeout")
  end)
end

function GitRunner._record_success()
  M._consecutive_timeouts = 0
end

function GitRunner._record_failure(reason)
  -- Non-timeout failures do not increment the timeout counter,
  -- but we still log for diagnostics.
  -- (Only timeouts trigger auto-disable.)
  vim.schedule(function()
    -- Could add to a log category here.
  end)
end

function GitRunner._record_timeout(on_timeout_cb)
  M._consecutive_timeouts = M._consecutive_timeouts + 1
  if on_timeout_cb then pcall(on_timeout_cb) end

  if M._consecutive_timeouts >= MAX_CONSECUTIVE_TIMEOUTS then
    M._git_disabled = true
    M._last_disable_reason = "too many consecutive git status timeouts"
    vim.schedule(function()
      vim.notify("BSI Git: disabled after " .. MAX_CONSECUTIVE_TIMEOUTS ..
                 " consecutive timeouts. Press :BSITreeGitEnable to re-enable.", vim.log.levels.WARN)
    end)
  end
end

--- Force re-enable after degradation (user or test command).
function M.enable_git_integration()
  M._git_disabled = false
  M._consecutive_timeouts = 0
  M._last_disable_reason = nil
  -- Also clear negative caches so we retry discovery
  M._toplevels_by_path = {}
end

function M.disable_git_integration(reason)
  M._git_disabled = true
  M._last_disable_reason = reason or "manual"
end

function M.is_git_integration_enabled()
  return not M._git_disabled
end

-- ---------------------------------------------------------------------------
-- Toplevel discovery (Phase 2)
-- ---------------------------------------------------------------------------

--- Discover the git toplevel for a given path.
--- Uses aggressive caching (positive + negative) + the "prefix ignored" short-circuit optimization
--- described in the plan to avoid calling rev-parse for deep ignored trees.
---@param start_path string
---@return string|false   toplevel or false when definitely not a git repo
function M.get_toplevel(start_path)
  if M._git_disabled then return false end

  local p = normalize_path(start_path)
  if M._toplevels_by_path[p] ~= nil then
    return M._toplevels_by_path[p]
  end

  -- The elite short-circuit (optimization #2 from nvim-tree analysis):
  -- Before *any* rev-parse, check if this path lives under a known project's ignored tree.
  -- If so, we can immediately return that project's toplevel (we already paid for discovery once).
  -- This turns the vast majority of lookups inside node_modules/, target/, etc. into pure Lua prefix checks.
  for _, proj in pairs(M._projects_by_toplevel) do
    if proj.files and proj.path_ignored_in_project and proj:path_ignored_in_project(p) then
      local tl = proj.toplevel
      -- Cache the negative-ish result for this deep path so future calls are instant.
      M._toplevels_by_path[p] = tl
      return tl
    end
  end

  -- Also do a quick "is this path under the working tree of any known project at all?"
  -- (helps even for non-ignored paths inside a large known repo after initial load)
  for _, proj in pairs(M._projects_by_toplevel) do
    local tl = proj.toplevel
    if p == tl or vim.startswith(p, tl .. "/") then
      M._toplevels_by_path[p] = tl
      return tl
    end
  end

  -- Actual discovery only when we have no prior knowledge
  local out = vim.system({
    "git", "-C", p, "rev-parse", "--show-toplevel", "--absolute-git-dir"
  }, { text = true }):wait()

  if not out or out.code ~= 0 or not out.stdout or out.stdout == "" then
    M._toplevels_by_path[p] = false
    return false
  end

  local lines = vim.split(out.stdout, "\n", { plain = true, trimempty = true })
  local toplevel = normalize_path(lines[1])

  M._toplevels_by_path[p] = toplevel
  M._toplevels_by_path[toplevel] = toplevel

  return toplevel
end

--- Check git config status.showUntrackedFiles for a toplevel (cached).
--- Returns true unless the value is explicitly "no".
function M.should_show_untracked(toplevel)
  if M._show_untracked_cache[toplevel] ~= nil then
    return M._show_untracked_cache[toplevel]
  end
  local out = vim.system({ "git", "-C", toplevel, "config", "status.showUntrackedFiles" }, { text = true }):wait()
  local val = ""
  if out and out.code == 0 and out.stdout then
    val = vim.trim(out.stdout or ""):lower()
  end
  local show = (val ~= "no")
  M._show_untracked_cache[toplevel] = show
  return show
end

-- ---------------------------------------------------------------------------
-- Project (owns per-repo state, Phase 2/3)
-- ---------------------------------------------------------------------------

---@class Project
---@field toplevel string
---@field files table<string, string>     -- abs_path -> XY (the raw porcelain map)
---@field dirs table                      -- { direct = { [dir]= {XY,...} }, indirect = { [dir]= {XY,...} } }
---@field watcher? any                    -- fs event handle(s) on critical .git files
---@field loaded_at number
local Project = {}
Project.__index = Project
M.Project = Project

---Create an empty Project shell (real population happens in load).
function Project.new(toplevel)
  return setmetatable({
    toplevel = normalize_path(toplevel),
    files = {},
    dirs = { direct = {}, indirect = {} },
    watcher = nil,
    loaded_at = vim.uv.now(),
  }, Project)
end

--- Returns true if the given absolute path has a direct "!!" entry in this project.
function Project:is_path_ignored(abs_path)
  local p = normalize_path(abs_path)
  local xy = self.files[p]
  if xy == "!!" then return true end

  -- Also honor directory prefixes we recorded
  if self._ignored_dir_prefixes then
    for _, pref in ipairs(self._ignored_dir_prefixes) do
      if p == pref or vim.startswith(p, pref .. "/") then
        return true
      end
    end
  end
  return false
end

-- Back-compat name used by some plan references.
Project.path_ignored_in_project = Project.is_path_ignored

--- Build the dirs aggregation (Phase 3).
--- direct[dir]   = list of XY for direct children whose *parent dir* == dir (non-ignored statuses only)
--- indirect[dir] = union of all descendant statuses (walk toward toplevel)
---
--- IMPORTANT per plan: "!!" entries are deliberately excluded from the dirs aggregation.
--- Ignored state for directories is carried by either:
---   - an explicit !! file entry for the dir itself, or
---   - parent_ignored propagation at attachment time.
function Project:_build_dirs()
  self.dirs = { direct = {}, indirect = {} }

  for abs, xy in pairs(self.files) do
    if xy == "!!" then
      -- Ignored entries do not populate direct/indirect. They are handled via files[] + parent prop.
      goto continue
    end

    local dir = vim.fn.fnamemodify(abs, ":h")
    -- direct
    if not self.dirs.direct[dir] then self.dirs.direct[dir] = {} end
    table.insert(self.dirs.direct[dir], xy)

    -- climb for indirect (all ancestors up to but not including toplevel root itself usually)
    local current = dir
    while current and #current >= #self.toplevel do
      if not self.dirs.indirect[current] then self.dirs.indirect[current] = {} end
      table.insert(self.dirs.indirect[current], xy)
      if current == self.toplevel then break end
      local parent = vim.fn.fnamemodify(current, ":h")
      if parent == current then break end
      current = parent
    end

    ::continue::
  end
end

--- Load (or reload) the project by running the runner and building the dirs index.
---@param path? string  optional path to limit status collection
function Project:load(path)
  if M._git_disabled then
    self.files = {}
    self.dirs = { direct = {}, indirect = {} }
    return
  end

  local map = GitRunner.run(self.toplevel, path)
  if not map then
    self.files = {}
    self.dirs = { direct = {}, indirect = {} }
    return
  end

  self.files = map
  -- Also store a fast list of ignored dir prefixes (for prefix checks)
  self._ignored_dir_prefixes = {}
  for p, xy in pairs(map) do
    if xy == "!!" and vim.fn.isdirectory(p) == 1 then
      table.insert(self._ignored_dir_prefixes, p)
    end
  end

  self:_build_dirs()
  self.loaded_at = vim.uv.now()
end

--- Async version of load.
---@param path? string
---@param done? fun(project: Project)
function Project:load_async(path, done)
  if M._git_disabled then
    self.files = {}
    self.dirs = { direct = {}, indirect = {} }
    if done then vim.schedule(function() done(self) end) end
    return
  end

  GitRunner.run_async(self.toplevel, path, {}, function(map)
    if map then
      self.files = map
      self._ignored_dir_prefixes = {}
      for p, xy in pairs(map) do
        if xy == "!!" and vim.fn.isdirectory(p) == 1 then
          table.insert(self._ignored_dir_prefixes, p)
        end
      end
      self:_build_dirs()
    else
      self.files = {}
      self.dirs = { direct = {}, indirect = {} }
    end
    self.loaded_at = vim.uv.now()
    if done then done(self) end
  end)
end

--- Targeted reload (used by watchers and explicit refresh on a subtree).
function Project:reload(path)
  self:load(path)
end

-- Simple internal debounce helper (avoids depending on external utils in the core git layer).
local function debounce(fn, delay_ms)
  local timer = nil
  return function(...)
    local args = {...}
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.uv.new_timer()
    timer:start(delay_ms or 150, 0, function()
      timer:stop()
      timer:close()
      timer = nil
      vim.schedule(function()
        fn(unpack(args))
      end)
    end)
  end
end

--- Start extremely narrow filesystem watching on the critical .git metadata files only.
--- This is the high-impact reactivity optimization (#5). We never watch the whole .git
--- or the working tree recursively.
function Project:start_watcher(on_change)
  if self.watcher or M._git_disabled then return end
  if not self.toplevel then return end

  local git_dir = self.toplevel .. "/.git"
  -- Some setups use a file at .git that points to the real dir (worktrees, submodules).
  -- For v1 we keep it simple and watch the conventional location.
  if vim.fn.isdirectory(git_dir) ~= 1 then
    -- Could be a gitfile; for now skip watcher (common case for main worktree is a dir).
    return
  end

  self._watcher_handles = {}
  self._on_change = on_change or function() self:reload() end

  local debounced_reload = debounce(function()
    -- Reload the status for the whole project (or could target if we had the changed file).
    self:reload()
    if self._on_change then
      pcall(self._on_change, self)
    end
  end, 120)

  for _, fname in ipairs(WATCHED_GIT_FILES) do
    local full = git_dir .. "/" .. fname
    -- Only start an event watcher if the file currently exists or we expect it might (HEAD usually does).
    local ev = vim.uv.new_fs_event()
    if ev then
      local ok = pcall(function()
        ev:start(full, {}, function(err, filename, events)
          if err then
            -- One bad watcher shouldn't kill others; just stop this one.
            pcall(function() ev:stop() end)
            return
          end
          -- Any of create/delete/change/rename on these files means "git state may have changed".
          debounced_reload()
        end)
      end)
      if ok then
        table.insert(self._watcher_handles, ev)
      else
        pcall(function() ev:stop() end)
      end
    end
  end

  self.watcher = true  -- marker that we have active narrow watchers
end

function Project:stop_watcher()
  if self._watcher_handles then
    for _, ev in ipairs(self._watcher_handles) do
      pcall(function()
        ev:stop()
        ev:close()
      end)
    end
    self._watcher_handles = nil
  end
  self.watcher = nil
end

-- ---------------------------------------------------------------------------
-- GitManager high level API (the "Project / Repository State Manager")
-- ---------------------------------------------------------------------------

local GitManager = {}
M.GitManager = GitManager

--- Ensure we have a Project for the toplevel of the given path.
--- Returns the Project (may be freshly loaded) or nil if not a git repo / disabled.
---@param any_path string
---@return Project|nil
function GitManager.load_project(any_path)
  if M._git_disabled then return nil end

  local toplevel = M.get_toplevel(any_path)
  if not toplevel then return nil end

  local proj = M._projects_by_toplevel[toplevel]
  if not proj then
    proj = Project.new(toplevel)
    M._projects_by_toplevel[toplevel] = proj
    proj:load()
    -- Start narrow .git watcher (only on the 5 critical files). This gives reactive
    -- updates when the user stages, commits, or changes HEAD without a manual R.
    proj:start_watcher(function(updated_proj)
      -- Future: notify any Tree instances rooted under this toplevel so they can
      -- refresh their _git_changes / snapshot / re-apply git_status without a full fs re-scan.
      -- For now the reload() inside the watcher already updated the Project data.
    end)
  end
  return proj
end

--- Async variant.
function GitManager.load_project_async(any_path, done)
  if M._git_disabled then
    if done then vim.schedule(function() done(nil) end) end
    return
  end

  local toplevel = M.get_toplevel(any_path)
  if not toplevel then
    if done then vim.schedule(function() done(nil) end) end
    return
  end

  local proj = M._projects_by_toplevel[toplevel]
  if not proj then
    proj = Project.new(toplevel)
    M._projects_by_toplevel[toplevel] = proj
  end

  proj:load_async(nil, function()
    if not proj.watcher then
      proj:start_watcher(function(updated_proj)
        -- See sync path comment.
      end)
    end
    if done then done(proj) end
  end)
end

function GitManager.get_project(toplevel)
  return M._projects_by_toplevel[toplevel]
end

function GitManager.reload_project(toplevel, path)
  local proj = M._projects_by_toplevel[toplevel]
  if proj then proj:reload(path) end
end

function GitManager.reload_all_projects()
  for _, proj in pairs(M._projects_by_toplevel) do
    proj:reload()
  end
end

function GitManager.purge_state()
  for _, proj in pairs(M._projects_by_toplevel) do
    pcall(function() proj:stop_watcher() end)
  end
  M._projects_by_toplevel = {}
  M._toplevels_by_path = {}
  M._show_untracked_cache = {}
end

--- Best-effort early exit for obviously ignored paths without hitting git at all.
--- Used by callers before get_toplevel when they have a live project.
function GitManager.path_ignored_in_any_project(path)
  local p = normalize_path(path)
  for _, proj in pairs(M._projects_by_toplevel) do
    if proj:is_path_ignored(p) then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Status attachment helpers (Phase 4 sketch — pure functions, easy to call from scan)
-- ---------------------------------------------------------------------------

--- Decide the git status descriptor for a *file* node.
--- parent_ignored wins and forces "!!".
---@param parent_ignored boolean
---@param project Project|nil
---@param abs_path string
---@return { file?: string }
function M.git_status_file(parent_ignored, project, abs_path)
  if parent_ignored then
    return { file = "!!" }
  end
  if not project or not project.files then
    return {}
  end
  local xy = project.files[normalize_path(abs_path)]
  if xy then
    return { file = xy }
  end
  return {}
end

--- Decide the git status descriptor for a *directory* node.
--- Returns the raw file entry (if the dir itself is tracked/ignored) plus the pre-aggregated
--- direct/indirect children status lists (excluding pure !! which live only in files + parent prop).
---@param parent_ignored boolean
---@param project Project|nil
---@param abs_path string
---@return { file?: string, dir?: { direct?: string[], indirect?: string[] } }
function M.git_status_dir(parent_ignored, project, abs_path)
  local res = M.git_status_file(parent_ignored, project, abs_path)
  if not project or not project.dirs then
    return res
  end
  local p = normalize_path(abs_path)
  local direct = project.dirs.direct[p]
  local indirect = project.dirs.indirect[p]
  if direct or indirect then
    res.dir = {
      direct = direct,
      indirect = indirect,
    }
  end
  return res
end

--- Convenience predicate used by nodes and filters.
function M.is_git_ignored(node_or_status)
  if type(node_or_status) == "table" then
    return node_or_status.git_status and node_or_status.git_status.file == "!!"
  end
  return node_or_status == "!!"
end

-- ---------------------------------------------------------------------------
-- Public surface (will grow with Phase 7)
-- ---------------------------------------------------------------------------

M.DEFAULT_TIMEOUT = DEFAULT_TIMEOUT

-- Convenience re-exports
M.run = GitRunner.run
M.run_async = GitRunner.run_async
M.parse = GitRunner.parse_porcelain_v1_z

return M
