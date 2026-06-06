-- ============================================================================
-- bsi.webify.url
-- ============================================================================
--
-- Single Responsibility: Build web URLs that point to files (and optionally
-- specific lines) inside a git repository hosted on a forge.
--
-- This module is mostly pure string/URL assembly. Given structured input
-- (host, user/org, repo, branch, relative file path, optional line), it
-- produces a ready-to-use https URL for the forge's web UI.
--
-- It deliberately does *not* know:
--   - How to obtain git remotes or run git commands (that's bsi.git)
--   - Current buffer / cursor state (that's webify/init.lua)
--   - How the resulting URL will be used (open, yank, etc.)
--
-- Forge-specific URL shape decisions (GitHub uses `/blob/`, GitLab uses
-- `/-/blob/`, etc.) are delegated to `bsi.git.remote`. This keeps the
-- classification logic in one authoritative place.
--
-- Expected input:
--   {
--     host           = "github.com" | "gitlab.com" | "git.example.com",
--     user           = "owner" | "group/subgroup",
--     repo           = "my-repo",
--     branch         = "main" | "feature/xyz",
--     relative_path  = "src/foo.lua" | "README.md",
--     line           = 42 | nil,
--   }
--
-- ============================================================================

local git = require("bsi.git")

local M = {}

--- Build a URL to a specific file (blob) in a git forge, optionally with a
--- line number fragment.
---
--- This is the main (currently only) entry point of the url submodule.
---
--- @param spec table  See module header for the expected shape.
--- @return string|nil  Fully qualified https URL, or nil if required fields missing.
function M.build_blob_url(spec)
  if type(spec) ~= "table" then
    return nil
  end

  local host          = spec.host
  local user          = spec.user
  local repo          = spec.repo
  local branch        = spec.branch
  local relative_path = spec.relative_path
  local line          = spec.line

  if not host or not user or not repo or not branch or not relative_path then
    return nil
  end

  -- Normalize: remove leading/trailing slashes from path pieces where it would
  -- create ugly double slashes in the final URL.
  relative_path = relative_path:gsub("^/+", ""):gsub("/+$", "")
  branch = branch:gsub("^/+", ""):gsub("/+$", "")

  if relative_path == "" then
    return nil
  end

  -- Ask the git layer for the correct blob path style.
  -- This centralizes the "GitHub vs GitLab (or other) URL shape" decision
  -- in bsi.git.remote instead of duplicating heuristics here.
  local blob_segment = git.remote.get_blob_path_style(host)

  -- Example GitHub:
  --   https://github.com/user/repo/blob/main/src/foo.lua
  -- Example GitLab (or self-hosted):
  --   https://gitlab.com/group/repo/-/blob/main/src/foo.lua
  local url = string.format(
    "https://%s/%s/%s%s%s/%s",
    host,
    user,
    repo,
    blob_segment,
    branch,
    relative_path
  )

  if line and type(line) == "number" and line > 0 then
    url = string.format("%s#L%d", url, line)
  end

  return url
end

--- Convenience wrapper when you already have a parsed remote table from
--- bsi.webify.remote plus the other pieces.
---
--- @param parsed_remote table  { host, user, repo }
--- @param branch string
--- @param relative_path string
--- @param line number|nil
--- @return string|nil
function M.build_from_remote(parsed_remote, branch, relative_path, line)
  if not parsed_remote then
    return nil
  end
  return M.build_blob_url({
    host          = parsed_remote.host,
    user          = parsed_remote.user,
    repo          = parsed_remote.repo,
    branch        = branch,
    relative_path = relative_path,
    line          = line,
  })
end

return M
