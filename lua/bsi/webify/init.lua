-- ============================================================================
-- bsi.webify
-- ============================================================================
--
-- Single Responsibility: Provide a high-level, editor-aware interface for
-- turning "the file I'm looking at right now" into a shareable web URL on
-- the project's git forge (GitHub / GitLab / etc.), and to act on that URL
-- (open in browser, yank to clipboard).
--
-- This is the only module most of the configuration should require directly:
--     local webify = require("bsi.webify")
--     webify.open_file_in_browser()
--     webify.yank_line_url()
--
-- Internal architecture (strict separation of concerns):
--   - bsi.git.remote      : knows how to parse git remote strings and classify
--                            the forge (GitHub vs GitLab URL shapes, etc.).
--                            This lives in git because remotes are fundamentally
--                            a git concept.
--   - bsi.webify.url      : knows how to synthesize a forge blob URL from
--                            structured coordinates. Delegates forge-specific
--                            decisions (path style) to git.remote.
--   - bsi.webify (this)   : knows about the current Neovim context (buffer,
--                            cursor) + how to obtain git metadata for the
--                            current working tree, and wires everything
--                            together to implement the user-facing actions
--                            (open, yank).
--
-- Public API (stable surface, used from remap.lua and elsewhere):
--   open_file_in_browser()   -- open current file at HEAD of current branch
--   open_line_in_browser()   -- same + #L<line> anchor
--   yank_file_url()          -- copy file URL to clipboard, return the string
--   yank_line_url()          -- copy with line anchor
--   get_file_url()           -- just compute and return the string (no side effects)
--   get_line_url()           -- same with line
--
-- All "open" operations go through bsi.system.open_url so that platform
-- differences and non-blocking behavior are centralized.
--
-- ============================================================================

local git    = require("bsi.git")
local system = require("bsi.system")
local nvim   = require("bsi.utils.nvim")

local url_builder = require("bsi.webify.url")

-- Note: remote parsing lives in bsi.git.remote (git remotes are a git concern).
-- We access it via the already-required `git` module below.

local M = {}

-- ============================================================================
-- Internal helpers – context gathering + URL assembly
-- ============================================================================

--- Compute the path of the current buffer relative to the git repository root.
---
--- Returns nil (and optionally notifies) when we cannot determine a clean
--- relative path. We are intentionally stricter and more explicit than the
--- original implementation (no silent whitespace mangling).
---
--- @return string|nil
local function get_current_file_relative_to_repo()
  local full_path = nvim.get_buffer_file_path()
  if not full_path or full_path == "" then
    return nil
  end

  local repo_root = git.get_repo_root()
  if not repo_root or repo_root == "" then
    return nil
  end

  -- Normalize trailing slashes on both sides so prefix matching is reliable.
  repo_root = repo_root:gsub("/+$", "")
  full_path = full_path:gsub("/+$", "")

  -- Must be inside the repo.
  local prefix_len = #repo_root
  if full_path:sub(1, prefix_len) ~= repo_root then
    vim.notify("webify: current file is not inside the git repository root", vim.log.levels.WARN)
    return nil
  end

  -- Extract the part after the repo root + one separator.
  local rel = full_path:sub(prefix_len + 2)
  if rel:sub(1, 1) == "/" then
    rel = rel:sub(2)
  end

  if rel == "" then
    -- We are at the repo root itself; some forges support this, but for a
    -- "file" URL it doesn't make much sense. Return nil to be explicit.
    return nil
  end

  return rel
end

--- Assemble a web URL for the currently open file (optionally with a line
--- number). This is the core "what URL would I share for this file?" logic.
---
--- All the git + buffer context lives here. The actual URL string construction
--- is delegated to bsi.webify.url so that URL shape rules can evolve
--- independently.
---
--- @param with_line boolean
--- @return string|nil
local function get_current_file_web_url(with_line)
  -- 1. Obtain the remote and convert it to https form (git layer responsibility).
  local remote = git.get_remote_origin()
  if not remote or remote == "" then
    vim.notify("webify: no remote origin configured for this repository", vim.log.levels.WARN)
    return nil
  end

  local https_remote = git.convert_remote_to_https(remote)
  if not https_remote or https_remote == "" then
    vim.notify("webify: failed to convert remote to https form", vim.log.levels.WARN)
    return nil
  end

  -- 2. Parse the remote into structured coordinates.
  -- Parsing now lives in bsi.git.remote (git remotes are a git concern).
  local parsed = git.remote.parse(https_remote)
  if not parsed then
    vim.notify("webify: could not parse remote URL: " .. https_remote, vim.log.levels.WARN)
    return nil
  end

  -- 3. Determine current branch.
  local branch = git.get_current_branch()
  if not branch or branch == "" then
    vim.notify("webify: could not determine current branch", vim.log.levels.WARN)
    return nil
  end

  -- 4. Compute the path inside the repo for the current buffer.
  local relative_path = get_current_file_relative_to_repo()
  if not relative_path then
    return nil
  end

  -- 5. Optional line number.
  local line = nil
  if with_line then
    line = nvim.get_cursor_line_number()
  end

  -- 6. Delegate pure URL construction.
  return url_builder.build_from_remote(parsed, branch, relative_path, line)
end

-- ============================================================================
-- Public API – actions and pure getters
-- ============================================================================

--- Open the current file (on the current branch) in the default browser.
--- Uses the forge's web UI (GitHub / GitLab blob view).
function M.open_file_in_browser()
  local url = get_current_file_web_url(false)
  if url then
    system.open_url(url)
  end
end

--- Same as open_file_in_browser, but includes a line number fragment (#L42)
--- so the browser will scroll to / highlight the current cursor line.
function M.open_line_in_browser()
  local url = get_current_file_web_url(true)
  if url then
    system.open_url(url)
  end
end

--- Compute the web URL for the current file and copy it to the system
--- clipboard. Returns the URL string (or nil on failure) so callers can
--- also use the value programmatically.
---
--- @return string|nil
function M.yank_file_url()
  local url = get_current_file_web_url(false)
  if url then
    nvim.save_to_clipboard(url)
  end
  return url
end

--- Like yank_file_url, but includes the current line number anchor.
---
--- @return string|nil
function M.yank_line_url()
  local url = get_current_file_web_url(true)
  if url then
    nvim.save_to_clipboard(url)
  end
  return url
end

--- Pure getter: return the web URL for the current file without performing
--- any side effects (no clipboard, no browser).
---
--- Useful for debugging, statuslines, or custom keymaps.
---
--- @return string|nil
function M.get_file_url()
  return get_current_file_web_url(false)
end

--- Pure getter with line number.
---
--- @return string|nil
function M.get_line_url()
  return get_current_file_web_url(true)
end

return M
