-- ============================================================================
-- bsi.git.remote
-- ============================================================================
--
-- Single Responsibility: Everything related to git *remote* strings and their
-- identity on the network / forge.
--
-- This submodule owns:
--   - Converting various remote formats (ssh, https) into clean https URLs.
--   - Parsing a remote URL into structured components {host, user, repo}.
--   - Classifying which forge / hosting service a remote belongs to
--     (GitHub, GitLab, self-hosted, etc.).
--   - Deciding presentation details + building common forge URLs
--     (blob at ref, commit, pipelines, etc.).
--
-- It is intentionally *string-oriented*. It does not run `git` commands
-- (those live in the parent `bsi.git` module). It receives remote URLs
-- that have usually been obtained via `git remote get-url ...`.
--
-- Builders that used to live in bsi.utils.ide (now bsi.ide) (build_commit_url, build_blob_url,
-- build_pipelines_url, and the *path_style getters) have been moved here.
--
-- Why this lives under `bsi.git`:
--   - Remotes are a core git concept.
--   - Several remote-string helpers already existed in bsi.git
--     (convert_remote_to_https, get_git_provider, convert_origin_to_project_name, ...).
--   - Web URL construction for "this file in the repo" is a natural
--     extension of "what is the public home of this repository?".
--
-- Consumers:
--   - bsi.webify (for building "open this file on GitHub/GitLab" links)
--   - bsi.ide (for opening repo, commit, blame, pipelines, MRs)
--   - fastgit and others that need project names or forge identity.
--
-- ============================================================================

local M = {}

-- -------------------------------------------------------------------------
-- Conversion
-- -------------------------------------------------------------------------

--- Convert an SSH or HTTPS git remote into a clean https URL.
--- Strips any trailing .git.
---
--- Examples:
---   git@github.com:user/repo.git  →  https://github.com/user/repo
---   https://github.com/user/repo.git → https://github.com/user/repo
---   git@gitlab.example.com:group/sub/repo → https://gitlab.example.com/group/sub/repo
---
--- @param ssh_or_https string
--- @return string
function M.convert_remote_to_https(ssh_or_https)
  local remote_url = ssh_or_https:gsub("%.git$", "")          -- Remove .git suffix
  remote_url = remote_url:gsub("git@([^:]+):", "https://%1/") -- Convert SSH to HTTPS
  return remote_url
end

-- Keep the old name some call sites used in tests/docs for compatibility.
M.convert_origin_to_https = M.convert_remote_to_https

--- Extract a "project path" suitable for some GitLab APIs from a (usually https) URL.
--- Example:
---   https://gitlab.selfhosted.net/myteam/subgroup/projectname.git
---   → "myteam/subgroup/projectname"
---
--- @param url string
--- @return string | nil
function M.convert_origin_to_project_name(url)
  return url:match("https?://[^/]+/(.+)%.git") or url:match("https?://[^/]+/(.+)")
end

-- -------------------------------------------------------------------------
-- Parsing
-- -------------------------------------------------------------------------

--- Parse a git remote (ssh or https form) into structured components.
---
--- @param remote_url string
--- @return table|nil   { host: string, user: string, repo: string } or nil
function M.parse(remote_url)
  if type(remote_url) ~= "string" or remote_url == "" then
    return nil
  end

  local host, namespace, repo

  -- Try https?:// form first (after possible conversion)
  local pattern = "^https?://([^/]+)/(.+)/([^/]+)$"
  host, namespace, repo = string.match(remote_url, pattern)

  if not host then
    -- Fallback without strict end
    pattern = "^https?://([^/]+)/(.+)/([^/]+)"
    host, namespace, repo = string.match(remote_url, pattern)
  end

  if not host then
    -- SSH form: git@host:user/repo(.git)?
    -- Also handles git@host:group/sub/repo
    pattern = "^git@([^:]+):(.+)/([^/]+)$"
    host, namespace, repo = string.match(remote_url, pattern)

    if not host then
      pattern = "^git@([^:]+):(.+)/([^/]+)%.git$"
      host, namespace, repo = string.match(remote_url, pattern)
    end
  end

  if not host or not namespace or not repo then
    return nil
  end

  -- Clean repo name
  repo = repo:gsub("%.git$", ""):gsub("/+$", "")
  if repo == "" then
    return nil
  end

  return {
    host = host,
    user = namespace, -- may contain slashes for GitLab subgroups
    repo = repo,
  }
end

--- Like parse, but returns nil (instead of partial table) if any required
--- piece is missing.
---
--- @param remote_url string
--- @return table|nil
function M.parse_or_nil(remote_url)
  local parsed = M.parse(remote_url)
  if parsed and parsed.host and parsed.user and parsed.repo then
    return parsed
  end
  return nil
end

-- -------------------------------------------------------------------------
-- Classification & Forge-specific presentation
-- -------------------------------------------------------------------------

local function normalize_for_classification(input)
  if type(input) ~= "string" then
    if type(input) == "table" and input.host then
      return input.host
    end
    return nil
  end

  -- If it still looks like an ssh remote, convert for easier matching
  local s = input
  if s:match("^git@") then
    s = M.convert_remote_to_https(s)
  end

  -- Extract host if it looks like a full URL now
  local host = s:match("^https?://([^/]+)")
  if host then
    return host
  end

  -- Otherwise assume it's already just a host or contains the host
  return s
end

--- Classify the forge type for a remote, URL, or host.
--- Returns "github", "gitlab", or nil.
---
--- This is the single source of truth for "is this GitHub-shaped or GitLab-shaped?".
---
--- @param remote_or_url_or_host string|table
--- @return "github"|"gitlab"|nil
function M.classify(remote_or_url_or_host)
  local key = normalize_for_classification(remote_or_url_or_host)
  if not key then
    return nil
  end

  key = key:lower()

  if key:find("github", 1, true) then
    return "github"
  elseif key:find("gitlab", 1, true) then
    return "gitlab"
  end

  return nil
end

--- Backward-compatible name (the old function in git/init.lua was get_git_provider).
--- It used to require a remote to be configured; the new classify is more flexible.
---
--- @return "github"|"gitlab"|nil
function M.get_git_provider(remote_or_url_or_host)
  if not remote_or_url_or_host then
    -- Old behavior tried to fetch current origin
    -- We keep a soft fallback here for callers that pass nothing.
    -- Prefer passing the value explicitly.
    return M.classify(vim.fn.systemlist({ "git", "remote", "get-url", "origin" })[1])
  end
  return M.classify(remote_or_url_or_host)
end

--- Returns the URL path segment used for file blobs on this forge.
--- GitHub family:  /blob/
--- GitLab family:  /-/blob/
--- Unknown:        /blob/  (reasonable default for many self-hosted forges)
---
--- These builders (and the path style helpers) were previously duplicated in
--- bsi.ide. They belong here because they are about remote/forge URL
--- construction, which is a git remote concern.
---
--- @param remote_or_url_or_host string|table|nil
--- @return string  e.g. "/blob/" or "/-/blob/"
function M.get_blob_path_style(remote_or_url_or_host)
  local forge = M.classify(remote_or_url_or_host)
  if forge == "github" then
    return "/blob/"
  elseif forge == "gitlab" then
    return "/-/blob/"
  else
    -- Default to GitHub style for unknown/self-hosted forges.
    -- Callers that care can pass a more specific value or override.
    return "/blob/"
  end
end

--- Returns the URL path segment used for commits.
--- GitHub family:  /commit/
--- GitLab family:  /-/commit/
---
--- @param remote_or_url_or_host string|table|nil
--- @return string
function M.get_commit_path_style(remote_or_url_or_host)
  local forge = M.classify(remote_or_url_or_host)
  if forge == "github" then
    return "/commit/"
  elseif forge == "gitlab" then
    return "/-/commit/"
  else
    return "/commit/"
  end
end

--- Returns the URL path segment used for pipelines / CI.
--- GitHub family:  /actions
--- GitLab family:  /-/pipelines
---
--- @param remote_or_url_or_host string|table|nil
--- @return string
function M.get_pipelines_path_style(remote_or_url_or_host)
  local forge = M.classify(remote_or_url_or_host)
  if forge == "github" then
    return "/actions"
  elseif forge == "gitlab" then
    return "/-/pipelines"
  else
    return "/-/pipelines"
  end
end

--- Build a full URL to a commit on the forge.
---
--- @param remote string|nil   Raw or https remote (e.g. from git.get_remote_origin())
--- @param hash string         Commit hash or ref
--- @return string|nil
function M.build_commit_url(remote, hash)
  if not remote or not hash then return nil end
  local https = M.convert_remote_to_https(remote)
  local seg = M.get_commit_path_style(https)
  return https .. seg .. hash
end

--- Build a full URL to a file (blob) at a specific ref (branch or commit hash).
--- This is the convenience version that takes a remote string.
---
--- For the more structured version (host/user/repo/...), see bsi.webify.url.build_blob_url.
---
--- @param remote string|nil
--- @param ref string                Branch or commit hash
--- @param relative_path string
--- @param line number|nil
--- @return string|nil
function M.build_blob_url(remote, ref, relative_path, line)
  if not remote or not ref or not relative_path then return nil end
  local https = M.convert_remote_to_https(remote)
  local seg = M.get_blob_path_style(https)
  local url = https .. seg .. ref .. "/" .. relative_path:gsub("^/+", "")
  if line and line > 0 then
    url = url .. "#L" .. line
  end
  return url
end

--- Build a URL to the pipelines / CI page.
---
--- @param remote string|nil
--- @return string|nil
function M.build_pipelines_url(remote)
  if not remote then return nil end
  local https = M.convert_remote_to_https(remote)
  local seg = M.get_pipelines_path_style(https)
  return https .. seg
end

return M
