-- ============================================================================
-- bsi.system
-- ============================================================================
--
-- MODULE PROPOSAL / SPECIFICATION
--
-- Purpose
-- -------
-- bsi.system is the single, thin abstraction layer for making the user's
-- operating system and desktop environment do things on behalf of Neovim.
--
-- Its main responsibility is "open things the user would normally open from
-- Finder / Explorer / their browser":
--   - local files and directories
--   - URLs (http, https, file:, etc.)
--   - web searches
--
-- It is intentionally NOT a general "run arbitrary shell commands" module.
-- For that, use bsi.utils.nvim.system_async / system_with_timeout or
-- vim.system directly.
--
-- Design Principles
-- -----------------
-- 1. Target to multiplantform, but only macos and linux
--    - macOS   (macunix)
--    - Linux   (unix, non-mac)
--
-- 2. Non-blocking and safe for the editor
--    - Never uses os.execute, vim.fn.system, or io.popen for user-initiated
--      "open" actions.
--    - Always uses vim.fn.jobstart(..., { detach = true }).
--    - The external program is fully detached; Neovim does not wait and does
--      not inherit the child process.
--
-- 3. Argument safety
--    - Arguments are always passed as Lua lists (true argv style) to jobstart.
--    - No string concatenation into a shell command.
--    - Paths containing spaces, single quotes, double quotes, $, `, etc. are
--      safe by construction.
--
-- 4. Minimal, focused surface
--    - Only operations that map to "the user's default handler for this thing".
--    - No attempt to parse output, wait for results, or control the launched app
--      after launch (at least in the current version).
--
-- 5. Predictable fallback behavior
--    - On unsupported platforms we notify at WARN level and return early.
--    - We do not throw or block.
--
-- Current Public API (as of this writing)
-- ---------------------------------------
--   M.open_url(url)
--       Open a URL or filesystem path with the OS default application.
--
--   M.search_google(text)
--       Convenience helper: URL-encode the given text and open it as a
--       Google search in the user's default browser.
--
-- Intended Usage Patterns
-- -----------------------
-- - From tree views (bsi.ui.tree, nvim-tree) when user presses "o" or similar:
--     system.open_url(node.path)
--
-- - From webify / git helpers to open remote URLs:
--     system.open_url("https://...")
--
-- - From keymaps for quick web search on a word or visual selection:
--     system.search_google(word_or_selection)
--
-- - From ide.lua helpers (open_git_repo, open_git_commit, etc.):
--     system.open_url(constructed_remote_url)
--
-- Future Directions (not yet implemented)
-- ---------------------------------------
-- - More deliberate search abstraction:
--     system.search(text, { engine = "google" | "ddg" | "kagi" | ... })
--   or separate functions (search_google, search_duckduckgo, ...)
--
-- - Platform-specific "reveal" operations:
--     system.reveal_in_finder(path)   -- macOS: open -R
--     system.reveal_in_explorer(path) -- Windows
--
-- - Open with a specific application (when the user wants to override default):
--     system.open_with(path, "Google Chrome")
--     system.open_with(path, "code")     -- VS Code, etc.
--
-- - Browser control helpers (focus existing tab, incognito, specific profile).
--
-- - Clipboard integration helpers that then open (e.g. "open whatever is in +).
--
-- - Async "did it succeed?" feedback (some platforms can report launch failure).
--
-- Non-Goals
-- ---------
-- - This module is not a process manager.
-- - This module is not a general command runner (see bsi.utils.nvim).
-- - This module does not attempt to parse or understand the content of what it
--   opens (it is a fire-and-forget launcher).
--
-- ============================================================================

local M = {}

--- Open a URL, file, or directory using the operating system's default handler.
---
--- This is the core primitive of bsi.system. It asks the desktop environment
--- to do what the user would normally do when double-clicking or "open"-ing
--- something:
---   - http/https URLs → default web browser (Chrome, Safari, Firefox, Edge, ...)
---   - file paths      → default application for that file type (editor, PDF viewer,
---                       image viewer, etc.)
---   - directory paths → Finder / Explorer / file manager
---
--- Platform behavior
--- -----------------
--- macOS (vim.fn.has("macunix") == 1):
---     Executes: open <url>
---     This is the standard macOS way to open anything with its registered
---     default application. Works for http, https, file:, directories, and
---     almost any UTI-registered type.
---
--- Linux (vim.fn.has("unix") == 1 and not macunix):
---     Executes: xdg-open <url>
---     The freedesktop.org standard way to delegate to the user's preferred
---     applications according to mime types and .desktop entries.
---
--- Windows (vim.fn.has("win32") == 1):
---     Executes: cmd.exe /c start "" <url>
---     The extra empty "" argument is required so that start treats the URL
---     as the command to run rather than a window title. Using the argv form
---     of jobstart still protects us from most quoting issues.
---
--- Safety and non-blocking guarantees
--- ----------------------------------
--- - The command is started with vim.fn.jobstart(cmd, { detach = true }).
--- - Neovim does not block waiting for the child.
--- - The child process is detached from Neovim's process group / session.
--- - Arguments are passed as a Lua table (true argv), not interpolated into
---   a shell string. Therefore paths like:
---       "/Users/me/My Project/file with spaces & 'quotes'.pdf"
---   are handled correctly without any manual escaping.
---
--- Error handling
--- --------------
--- - If the current platform is not recognized, a warning is shown via
---   vim.notify(..., vim.log.levels.WARN) and the function returns early.
--- - We do not attempt to capture or interpret the exit status of the launched
---   program. From Neovim's perspective this is a best-effort "please open this"
---   request.
--- - If the external handler itself fails (e.g. no browser registered, broken
---   xdg-mime database), that failure is invisible to us (the launched program
---   may show its own error dialog or do nothing).
---
--- Parameters
--- ----------
--- @param url string
---        The thing to open. Can be:
---          - A web URL: "https://github.com/...", "http://..."
---          - A local file: "/absolute/path/to/file.lua", "relative/path.md"
---          - A directory: "/Users/me/projects/my-repo"
---          - Anything else the OS "open" command understands on that platform
---            (e.g. "file:///...", mailto:, vscode://, etc.)
---
--- Return value
--- ------------
--- Always returns nil. This is a fire-and-forget operation.
---
--- Examples
--- --------
---     -- Open a remote URL (used by webify, ide helpers, etc.)
---     system.open_url("https://gitlab.com/org/repo/-/merge_requests")
---
---     -- Open the current file's directory from a tree
---     system.open_url(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h"))
---
---     -- Open a file that may contain spaces and quotes
---     system.open_url("/tmp/report - final (v2).pdf")
---
--- See also
--- --------
--- - bsi.ui.tree: uses this for the "o" (open with system) action.
--- - bsi.utils.ide: many git-web helpers delegate to this after constructing URLs.
--- - lua/plugin/nvim-tree.lua: extra "o" / "of" mappings also use it.
function M.open_url(url)
  local cmd

  if vim.fn.has("macunix") == 1 then
    cmd = { "open", url }

  elseif vim.fn.has("unix") == 1 then
    cmd = { "xdg-open", url }

  elseif vim.fn.has("win32") == 1 then
    -- NOTE: the empty string "" as the second argument to "start" is
    -- intentional and required. Without it, start interprets the first
    -- token after "start" as the window title.
    cmd = { "cmd.exe", "/c", "start", '""', url }

  else
    vim.notify("Unsupported OS for open_url", vim.log.levels.WARN)
    return
  end

  vim.fn.jobstart(cmd, { detach = true })
end

--- Open a Google search for the given text in the user's default browser.
---
--- This is a convenience wrapper around open_url. It performs a very simple
--- transformation of the input text into a Google search URL and then delegates
--- to the platform-appropriate opener.
---
--- Encoding notes
--- --------------
--- The current implementation only replaces spaces with "%20". It does NOT
--- perform a full percent-encoding of the query string. In practice this is
--- "good enough" for the common case of searching for a word, symbol, or short
--- phrase copied from code or a buffer.
---
--- For more complex input (newlines, special characters, very long selections)
--- callers may want to do more thorough encoding before calling this function,
--- or we may evolve this into a more robust helper in the future.
---
--- See the module header for discussion of possible future generalizations
--- (system.search(text, {engine = "..."}) etc.).
---
--- Parameters
--- ----------
--- @param text string
---        The text the user wants to search for. Typically:
---          - A word under the cursor
---          - The current visual selection
---          - A short error message or symbol name
---
---        The value is used as the "q" query parameter to Google.
---
--- Behavior
--- --------
--- 1. Spaces inside `text` are replaced by "%20".
--- 2. The resulting string is appended to "https://www.google.com/search?q=".
--- 3. The constructed URL is passed to M.open_url(...).
---
--- The call is non-blocking (see open_url documentation).
---
--- Return value
--- ------------
--- Always nil (fire-and-forget).
---
--- Examples
--- --------
---     -- Search for the word under cursor (common "<leader>sw" style mapping)
---     local word = require("bsi.utils.nvim").get_cursor_word()
---     system.search_google(word)
---
---     -- Search whatever is visually selected
---     local selection = require("bsi.utils.nvim").get_visual_selection()
---     system.search_google(selection)
---
---     -- Search a literal phrase with spaces
---     system.search_google("how to escape lua patterns")
---
--- See also
--- --------
--- - remap.lua: contains the keymaps that feed words / selections into this.
--- - open_url: the underlying mechanism that actually launches the browser.
function M.search_google(text)
  -- Very lightweight encoding: only spaces are turned into %20.
  -- This is intentionally simple; see the big comment above for caveats
  -- and future evolution plans.
  local encoded_text = text:gsub(" ", "%%20")

  local search_url = "https://www.google.com/search?q=" .. encoded_text

  M.open_url(search_url)
end

return M
