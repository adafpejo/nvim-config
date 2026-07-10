# BSI Tree

Modern, embedded file tree for the BSI Neovim UI layer.

**Location:** `lua/bsi/ui/tree.lua`  
**Entry point:** `require("bsi.ui.tree")`  
**Setup:** Called automatically from `lua/bsi/init.lua`

---

## Overview

The BSI Tree provides a lightweight, fast, git-aware file tree that can be opened as a sidebar or embedded inside custom layouts. It is **not** a replacement for `nvim-tree` (which is also installed); it is a purpose-built component for the three custom UI layouts (`<leader>u1` / `u2` / `u3`).

Key characteristics:
- Clean three-class architecture (Renderer / Provider / Tree)
- Deep git integration (porcelain status + numstat line counts + directory summaries)
- Automatic current-file tracking across all open tree instances
- Designed to live alongside (not fight) the rest of the editor

---

## Architecture

| Component   | Responsibility |
|-------------|----------------|
| `Renderer`  | Pure rendering: turns a flat list of visible nodes into buffer lines + extmarks/highlights |
| `Provider`  | Filesystem scanning + git data collection (`_get_git_changes`, `_get_git_numstats`, `scan`) |
| `Tree`      | High-level orchestrator. Owns state, visible nodes, expansion, refresh, keymaps, and the public instance API |
| `M` (module) | Factory + global registry (`M.instances`) + setup + `toggle_tree` |

The tree never writes to the filesystem except through explicit user actions (`a`, `d`, rename). All scanning is read-only.

---

## Data Model

### `bsi.Node`

```lua
---@class bsi.Node
---@field id string              -- usually the absolute path (used for expansion state)
---@field name string
---@field path string            -- absolute path
---@field type "file"|"directory"|"root"
---@field depth integer
---@field expanded boolean
---@field children bsi.Node[]|nil
---@field git_status string|nil  -- raw porcelain or internal DIR_* marker
---@field git_numstat table|nil  -- {added: number, deleted: number}
---@field git_status_summary string|nil -- e.g. "DMA", "AM", "D"
```

### Special `git_status` values (internal)

These are synthesized by the Provider during aggregation:

- `"DIR_ADDED"` — every child is a staged addition / untracked
- `"DIR_UNTRACKED"` — every child is untracked
- `"DIR_PARTIAL"` — mixed staged/unstaged changes
- `"DIR_MULTI:ADM?"` — multiple different change types (characters are the raw porcelain letters, sorted)

`git_status_summary` (the source of the `[DMA]` postfix) is a normalized, deduplicated string containing only `D`, `M`, `A` in that order.

---

## Core Features

### 1. Filesystem Scanning
- Recursive `vim.loop.fs_scandir` + `fs_lstat` (with bounded initial depth for interactive trees and on-demand expansion for subdirs)
- Hard-coded name-based ignore list (fast path, no git): `node_modules`, `vendor`, `dist`, `build`, `target`
- **Dotfiles** (names starting with `.` such as `.github/`, `.env*`, etc.) are **always** included.
- `.git` is treated as git-ignored: hidden by default in the filter, but shown (in grey) when `show_ignored=true`. Deep contents are kept shallow for performance.
- Gitignore (`.gitignore` rules) controls gray rendering (`BSITreeGitIgnored`) and filtering of ignored entries. `show_ignored` (default `true`) controls whether they are shown (greyed) or hidden. Uses a **single** `git status --porcelain=v1 -z --ignored=matching` snapshot per root (plus parent propagation and Lua prefix checks). Per-path `git check-ignore` is a legacy fallback only. This replaced the O(N) process spawns that caused the post-gray-rendering perf collapse on large ignored trees.
- Deleted files that still appear in `git status --porcelain` are synthesized into the tree even if they no longer exist on disk
- Initial open of the main tree only materializes a shallow view (root direct children + ancestors of the current editing buffer). Everything else is populated lazily when toggled or targeted by find/navigate.

### 2. Git Status (porcelain)
- Full `git status --porcelain` parsing (staged + unstaged)
- Untracked directories are recursively expanded and every file inside is marked `??`
- Parent directories are marked so that a change deep in the tree lights up all ancestors
- Handles renames (`old -> new` and quoted paths)

### 3. Git Line Changes (`+N-M`)
- Collected via `git diff --numstat` + `git diff --cached --numstat` (staged + unstaged merged)
- Displayed **after the filename** for every file that has non-zero changes:
  - mixed: ` +3-4`
  - pure add: ` +7`
  - pure delete (removal): ` -12`
- Only shown when `added > 0 or deleted > 0`
- Binary files and files with no diff stats are omitted

### 4. Directory Change Summary Postfix `[DMA]`
- Every directory node that contains any git-tracked changes receives a `git_status_summary` (e.g. `"DMA"`, `"AM"`, `"D"`)
- Rendered as ` [DMA]` immediately after the directory name
- The summary bubbles up through nested directories

### 5. Coloring Rules (current)
- **Files** — no single-character git status is rendered at the end of file lines anymore.
  - The inline detail (right after the filename) is colored:
    - `+NN` (or `+NN` part of `+NN-MM`) → green (`BSITreeGitAdded`)
    - `-MM` (or whole ` -MM` for pure removal) → red (`BSITreeGitDeleted`)
  - Examples:
    - `TODO.md +34-23` → `+34` green, `-23` red
    - `deleted.txt -12` → entire `-12` in red (`BSITreeGitDeleted`)
    - `new.txt +5` → `+5` green
  - Pure removals use a leading `-N` (no spurious `+0`) and render fully in the deletion color.
- **Directories with git changes**: both the directory name and the `[DMA]` (or `[AM]`, `[D]`, etc.) postfix are colored purple (`Special`).
- The filename text itself still receives a `name_hl` based on git status (`DiagnosticOk`/`Warn`/`Error`) for quick visual scanning.

### 6. Single-Child Directory Collapsing
- If a directory contains exactly one child that is also a directory, the two are inlined:
  - `foo/bar/baz/` becomes `foo/bar/baz` (with the deeper children promoted)
  - `id`, `path`, `name`, `git_*` fields are updated
  - Depth is renormalized
- This keeps deep but uninteresting directory chains compact

### 7. Expansion & Visibility
- Root and depth < 2 directories start expanded
- `get_visible_nodes()` performs a depth-first walk respecting the `expanded` flag (with simple caching across renders when no expansion/root mutation occurred)
- `render()` flattens to visible list (no deepcopy) and asks Renderer to render; display depth is computed as node.depth-1 inside the renderer (root is filtered before visible list)

### 8. Lazy Loading & Bounded Initial Scans (Performance)
- Initial tree construction for interactive views (not `git_only`) uses a bounded scan (`max_depth` at root) so the whole FS and huge subtrees are not walked on `<leader>ee` / u1 etc. Only direct children of the root are populated at open time.
- Git mode (`git_only`) uses a git-pruned scan (leveraging the porcelain status map + ancestor "dir" markers) when the git data is ready or on toggle. This scans exactly the files/dirs needed to show changes and builds the full default directory hierarchy (intermediate folders) for them. No artificial depth limit for the git-relevant structure.
- The single tracked "opened buffer" (the file the user is actively editing) seeds the view: `find_file` (called from BufEnter sync guard + explicitly after open) expands the ancestor chain to the current file using targeted on-demand `Provider:scan`. Because dotfiles are always present, this works for files inside hidden directories (e.g. opened via Telescope from `.github/`, `.config/`, etc.).
- When you toggle a directory whose children have never been scanned (`children == {}`, `_unpopulated`, or `_shallow_ignored`), a targeted `Provider:scan` is performed using the cached `_git_changes` / `_git_numstats` from the parent Tree instance.
- Works in both normal mode and `git_only` mode.
- Git-ignored directories (shown when `show_ignored`) use shallow population: only direct children are listed on open; their subdirectories stay as collapsed stubs. This keeps render/scan cost low for massive ignored trees (node_modules, vendor, dist, etc.). Subdirs are populated on-demand when the user explicitly toggles them. No blanket "expand all" under ignored dirs.
- Gitignore decisions are driven by a **one-shot snapshot** (`git status --porcelain=v1 -z --ignored=matching`) taken once per Tree root/refresh. The old per-path `git check-ignore` is only a fallback. Combined with `under_ignored` propagation and exact/prefix Lua checks, the cost of "is this gray/should we skip?" is now ~1 process + fast table lookups instead of one process per file. This is the main fix for the post-gray-rendering perf regression on large repos. (Modeled on nvim-tree's GitRunner + parent_ignored + disable_for_dirs patterns.)

### 9. Git-Only Mode (`git_only = true`)
- Used by layout "2" (`<leader>u2`) and `<leader>ge`
- Any path that does **not** appear in the git status map is pruned from the tree
- Renders using the normal directory tree structure (with folders) containing only changed items and the directories leading to them.
- On entering the mode (or initial open in git mode) a git-pruned scan is performed so *all* changed files are present in their natural dir hierarchy (including removed files synthesized from status). Toggle with `g` inside the tree also (re)scans for structure.

### 10. Current File Tracking
- On `BufEnter` to a *real file buffer*, if the path differs from last synced, every live tree instance calls `find_file()` (guarded to avoid redundant work on help/quickfix/terminals/tree-buf etc.)
- The tree will expand every ancestor directory as needed and move the cursor to the file
- The current file row receives the `BSITreeCurrentFile` background highlight

### 11. Auto-Refresh Triggers
- `BufAdd`, `BufDelete`, `BufWipeout` → all live trees re-render (now lighter: often cache hit on visible list, no deepcopy)
- BufEnter on the tree buffer itself → only cheap `render()` (no full refresh/git rescan)
- Manual `R` inside a tree buffer forces a full re-scan + git status refresh while preserving expansion state
- Cursor moves inside tree: zero-cost (native cursorline + winhighlight mapped to BSITreeCursorLine)

### 12. Actions from the Tree Buffer
- `<CR>`: toggle directory / open file (in editor)
- `o`: open file/directory with system default app (Finder, Preview, browser, etc.)
- `a`: add a new file in the selected directory (supports nested paths)
- `r` / `u`: rename or move the selected file/directory
- `g`: toggle git-changes-only view (same buffer; re-scans to show only modified/untracked)
- `d`: delete the selected file or directory (with confirmation)
- `D`: open `DiffviewOpen -- <file>`
- `y` / `Y`: yank name or relative path (also to `+` register)
- `R`: refresh
- `q`: close the tree window

Mouse support: single left-click selects the node, double-click opens the file or toggles directories.

---

## Public API

```lua
local tree = require("bsi.ui.tree")

-- Create and open a new tree
local t = tree.new({ root = "/path/to/repo", git_only = true })
t:open()

-- Programmatic control
t:refresh()
t:find_file("/absolute/path/to/file.lua")
t:toggle_git_mode()        -- switch this tree instance to/from git-changes view (same buffer)
t:get_root_path()          -- "~/projects/foo"

-- Global helpers
tree.toggle_tree()         -- open or close the (current mode) tree
tree.show_in_git_mode()    -- ensure visible + switch to git mode (for <leader>ge)
tree.get_root_path(bufnr)  -- read vim.b[bufnr].bsi_tree_root
tree.instances             -- table<bufnr, Tree> of all live trees
```

### Options accepted by `Tree.new(opts)`

| Option      | Type    | Default          | Description |
|-------------|---------|------------------|-------------|
| `root`      | string  | `vim.fn.getcwd()` | Root directory to scan |
| `expand_all`| boolean | false            | Force every directory open |
| `git_only`  | boolean | false            | Only show paths that appear in git status |
| `bufnr`     | number  | (created)        | Reuse an existing buffer |
| `winid`     | number  | (created)        | Reuse an existing window |

---

## Keybindings (inside Tree buffer)

All are buffer-local and silent.

| Key          | Action                              |
|--------------|-------------------------------------|
| `R`          | Refresh (re-scan + preserve expansion) |
| `h`          | Toggle visibility of git-ignored items (including .git; dotfiles always visible; shown in grey) |
| `q`          | Close window                        |
| `<CR>`       | Toggle dir / open file (in editor)  |
| `o`          | Open with system default app (Finder/Preview/etc) |
| `d`          | Delete file or directory (confirm)  |
| `D`          | `DiffviewOpen -- <file>`            |
| `a`          | Add new file in selected directory  |
| `r` / `u`    | Rename / Move file or directory     |
| `g`          | Toggle git-changes view (same buffer) |
| `y`          | Yank filename                       |
| `Y`          | Yank path relative to tree root     |
| `<LeftMouse>`| Select node (move cursor)           |
| `<2-LeftMouse>` | Open file (editor) / Toggle directory |

Global:
- `<leader>ee` → `M.toggle_tree()` (toggle visibility of the tracked main tree buffer; mode preserved)
- `<leader>ge` → `M.show_in_git_mode()` (ensure the main tree buffer is visible + in git-changes mode; always the one buffer)
- Inside any tree buffer: `g` → `toggle_git_mode()` (fast in-memory filter switch between full and git view on same buffer)
- `:BSITree [dir]` → open a tree rooted at the given directory (or cwd)

---

## Integration with UI Layouts

The tree is a first-class citizen of the three custom layouts:

- **Layout 1** (`<leader>u1`): Tree (left) + main buffer
- **Layout 2** (`<leader>u2`): `git_only` Tree (left) + branches + commits + git status (vertical splits below)
- **Layout 3** (`<leader>u3`): Pure git command views (no tree)

Window navigation with `1`/`2`/`3`/`4` works inside Tree and GitView buffers.

The `bsi.ui.context` module tracks all windows/buffers created by layouts so they can be closed together when switching layouts.

---

## Highlights

Defined in `M.setup()`:

- `BSITreeCurrentFile` — background highlight for the row matching the currently focused file (`#3b4261` + bold)
- `BSITreeOpenedFile` — defined but currently unused (legacy)

The tree defines these custom highlight groups (set in `M.setup()`):

- `BSITreeCurrentFile`
- `BSITreeGitAdded` (green) — used for the `+NN` part of file deltas
- `BSITreeGitModified` (orange) — available for filename highlighting on modifications
- `BSITreeGitDeleted` (red) — used for the `-MM` part of file deltas and full stats on removed files
- `BSITreeGitIgnored` (grey) — used for git-ignored files/dirs when shown
- `BSITreeGitIgnored` (grey) — used for files and directories that match .gitignore (when `show_ignored=true`)

It also uses `"Special"` (purple) for directories that contain any git changes (both the directory name and the `[DMA]` postfix). The filename text still uses the colorscheme's `Diagnostic*` groups via `name_hl`.

---

## Limitations & Known Behaviors

- Git data collection is now **asynchronous** (`vim.system` via `bsi.cmd` + `GitRunner` in `bsi.git.status`). The initial tree renders instantly from a cheap bounded FS scan; git status/numstat/ignored data is attached in the background. Large repos still pay for 1–2 git processes (the centralized porcelain=v1 -z snapshot), not one-per-file.
- Default `show_ignored=true`: gitignored items (including the `.git` directory and its top-level contents) are shown by default, rendered using `BSITreeGitIgnored` (grey). `.git` is never deeply traversed.
- The old fixed status column heuristic and trailing single-char status for files have been removed (inline colored `+N-M` and per-letter directory summaries are used instead).
- `print()` for yank feedback has been replaced with `vim.notify`.
- No horizontal scrolling help; very deep trees or extremely long names can become hard to read.
- The module assumes a Unix-like environment (forward slashes, `git` in PATH).
- Cursor movement inside the tree uses native `cursorline` + `winhighlight` (no render cost). Full re-render only on structural changes or tracked file change.
- `BSITreeOpenedFile` highlight group exists but does nothing (the feature was commented out).
- Multiple simultaneous trees on different roots are supported via `M.instances`, but only the most recently focused one receives `BufEnter` auto-follow in some edge cases.
- Legacy per-path `git check-ignore` and the old sync `Provider` git getters have been removed. Gitignore decisions rely on the one-shot snapshot + prefix + Project parent propagation.
- Directory change synthesis (DIR_* / DMA summaries) is now centralized in `bsi.git.status.compute_dir_git_status`.

---

## Future / Wishlist (not implemented)

- Right-aligned git detail column that respects actual window width
- Configurable ignore patterns
- LSP diagnostic counts next to files
- Better handling of submodules and worktrees
- Full watcher-driven live refresh of open trees without pressing R (basic Project watchers exist; tree notification wiring is partial)
- More complete use of Project.dirs aggregation inside the tree (currently tree still maintains some parallel change maps)

---

*Document updated during bsi-tree analysis + remediation (2026-07). Key fixes: dead legacy code removed, check-ignore eliminated, synthesis centralized in bsi.git.status, yank uses notify, git collection is async, snapshot+Project is the source of truth for ignored.*
