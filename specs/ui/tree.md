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

The tree never writes to the filesystem except through explicit user actions (`o`, `d`). All scanning is read-only.

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
- Recursive `vim.loop.fs_scandir` + `fs_lstat`
- Hard-coded ignore list: `node_modules`, `.git`, `vendor`, `dist`, `build`, `target`
- Deleted files that still appear in `git status --porcelain` are synthesized into the tree even if they no longer exist on disk

### 2. Git Status (porcelain)
- Full `git status --porcelain` parsing (staged + unstaged)
- Untracked directories are recursively expanded and every file inside is marked `??`
- Parent directories are marked so that a change deep in the tree lights up all ancestors
- Handles renames (`old -> new` and quoted paths)

### 3. Git Line Changes (`+N-M`)
- Collected via `git diff --numstat` + `git diff --cached --numstat` (staged + unstaged merged)
- Displayed **after the filename** for every file that has non-zero changes: ` +34-12`
- Only shown when `added > 0 or deleted > 0`
- Binary files and files with no diff stats are omitted

### 4. Directory Change Summary Postfix `[DMA]`
- Every directory node that contains any git-tracked changes receives a `git_status_summary` (e.g. `"DMA"`, `"AM"`, `"D"`)
- Rendered as ` [DMA]` immediately after the directory name
- The summary bubbles up through nested directories

### 5. Coloring Rules (current)
- **Files** — no single-character git status is rendered at the end of file lines anymore.
  - The inline ` +N-M` detail (right after the filename) is **always split-colored**:
    - `+NN` portion → green (`BSITreeGitAdded`)
    - `-MM` portion → red (`BSITreeGitDeleted`)
  - Example: `TODO.md +34-23` renders `+34` in green and `-23` in red.
  - This split applies to pure additions (`+120-0`), pure deletions (`+0-45`), and real modifications alike.
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
- `get_visible_nodes()` performs a depth-first walk respecting the `expanded` flag
- `render()` does a `vim.deepcopy` of visible nodes and decrements depth by one for display (root is never shown)

### 8. Lazy Loading
- When you toggle a directory whose children have never been scanned (`children == {}`), a targeted `Provider:scan` is performed using the cached `_git_changes` / `_git_numstats` from the parent Tree instance
- Works in both normal mode and `git_only` mode

### 9. Git-Only Mode (`git_only = true`)
- Used by layout "2" (`<leader>u2`)
- Any path that does **not** appear in the git status map is pruned from the tree
- Only directories and files that have changes (or contain changes) are shown

### 10. Current File Tracking
- On every `BufEnter`, every live tree instance calls `find_file()` on the newly entered buffer
- The tree will expand every ancestor directory as needed and move the cursor to the file
- The current file row receives the `BSITreeCurrentFile` background highlight

### 11. Auto-Refresh Triggers
- `BufAdd`, `BufDelete`, `BufWipeout` → all live trees re-render (cheap, just re-flattens + redraws)
- Manual `R` inside a tree buffer forces a full re-scan + git status refresh while preserving expansion state

### 12. Actions from the Tree Buffer
- `<CR>` or click: toggle directory / open file
- `o`: open file in the window to the right (`wincmd l`)
- `d`: open `DiffviewOpen -- <file>`
- `y` / `Y`: yank name or relative path (also to `+` register)
- `R`: refresh
- `q`: close the tree window

Mouse support: single left-click toggles, double-click toggles/opens.

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
t:get_root_path()          -- "~/projects/foo"

-- Global helpers
tree.toggle_tree()         -- open or close the last tree
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
| `q`          | Close window                        |
| `<CR>`       | Toggle dir / open file              |
| `o`          | Open file (focus right window)      |
| `d`          | `DiffviewOpen -- <file>`            |
| `y`          | Yank filename                       |
| `Y`          | Yank path relative to tree root     |
| `<LeftMouse>`| Move cursor                         |
| `<LeftRelease>` / `<2-LeftMouse>` | Toggle / open |

Global:
- `<leader>et` → `M.toggle_tree()`
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
- `BSITreeGitDeleted` (red) — used for the `-MM` part of file deltas

It also uses `"Special"` (purple) for directories that contain any git changes (both the directory name and the `[DMA]` postfix). The filename text still uses the colorscheme's `Diagnostic*` groups via `name_hl`.

---

## Limitations & Known Behaviors

- Git operations (`status`, `diff --numstat`) are currently **synchronous** (`io.popen` + `vim.fn.system`). Large repositories can cause noticeable lag on first open or `R`.
- The fixed status column (`status_col = 34`) is a heuristic; very long filenames + git detail can push the single-char prefix far to the right.
- `print()` is still used for yank feedback (should be `vim.notify`).
- No horizontal scrolling help; very deep trees or extremely long names can become hard to read.
- The module assumes a Unix-like environment (forward slashes, `git` in PATH).
- `BSITreeOpenedFile` highlight group exists but does nothing (the feature was commented out).
- Multiple simultaneous trees on different roots are supported via `M.instances`, but only the most recently focused one receives `BufEnter` auto-follow in some edge cases.

---

## Future / Wishlist (not implemented)

- Async git data collection (`vim.system`)
- Right-aligned git detail column that respects actual window width
- Configurable ignore patterns
- LSP diagnostic counts next to files
- Better handling of submodules and worktrees
- Replace `print` with `vim.notify`

---

*Document generated from the live implementation as of the latest edits (trailing single-char status removed for files + `+NN` always green / `-MM` always red split on file deltas + purple directories for any git changes).*
