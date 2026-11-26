# ui/tree Specification

## Purpose

Provide a filesystem-only file tree sidebar for the BSI Neovim UI. A bounded, ignore-aware directory scanner feeds a left-split listing that navigates, creates, moves, copies, and deletes paths, shows gitignore and dirty-file decorations without a git-only mode, and stays interactive on large folders.

## Requirements

### Requirement: Scanner is a filesystem module, not UI

The directory scanner SHALL be a standalone filesystem component. Invoking it MUST NOT create buffers, windows, or highlight groups, and MUST NOT load icon plugins. Returned nodes SHALL describe path, name, type (`file` | `directory` | `root`), depth, expansion stubs, and children. Nodes MAY include gitignore status and file numstat derived after the listing. They MUST NOT require icon or highlight fields to be valid.

#### Scenario: Scan without a tree window

- **WHEN** a caller scans a temporary directory with no UI session setup beyond headless Neovim
- **THEN** the scan returns a node tree
- **AND** no tree buffer or window is created

#### Scenario: Nodes carry no presentation fields

- **WHEN** a file node is produced
- **THEN** it has `path`, `name`, and `type` `"file"`
- **AND** it does not require icon or highlight fields to be valid

#### Scenario: Gitignore status is data, not presentation

- **WHEN** a scanned file is marked gitignored
- **THEN** the node includes gitignore status
- **AND** it still does not require icon or highlight fields to be valid

### Requirement: Bounded one-level directory scan

When scanning a directory without expand-all, the scanner SHALL return that directory’s direct children only. Child directories SHALL be unpopulated stubs (no recursive descent into their contents). Expand-all MAY populate the full subtree.

#### Scenario: Wide directory with nested children

- **WHEN** a directory contains at least 1000 files and several subdirectories that each contain nested files
- **AND** the scanner runs a one-level (non expand-all) scan of that directory
- **THEN** the result includes those files and subdirectory stubs as direct children
- **AND** no nested file from inside a child directory appears in the result tree

#### Scenario: Expand-all populates descendants

- **WHEN** a small nested directory is scanned with expand-all
- **THEN** descendant files under child directories are present in the result tree

### Requirement: Name-based ignore skips heavy directories

When ignored names are hidden, the scanner SHALL skip directories named `node_modules`, `vendor`, `dist`, `build`, `target`, and `.git`, and SHALL NOT descend into them. Dotfiles other than `.git` SHALL still be included.

#### Scenario: Huge node_modules is skipped

- **WHEN** a directory contains a `node_modules` folder with thousands of nested files and ignored names are hidden
- **AND** the scanner scans that directory
- **THEN** `node_modules` is absent from the children
- **AND** the scan does not enumerate files inside `node_modules`

#### Scenario: Ignored names are visible when shown

- **WHEN** the same directory is scanned with ignored names shown
- **THEN** `node_modules` appears as a child

#### Scenario: Dotfiles remain visible

- **WHEN** a directory contains `.env` and `.git` and ignored names are hidden
- **THEN** `.env` is present
- **AND** `.git` is absent

### Requirement: Stable child order and single-child collapse

Direct children SHALL be ordered directories before files, then by case-insensitive name, with `.git` (when shown) before other dot-directories. A directory whose only child is another directory SHALL collapse into a single `parent/child` name node, preserving the grandchild list.

#### Scenario: Directories sort before files

- **WHEN** a directory contains `a.txt` and `b/`
- **THEN** the first child is directory `b`
- **AND** the second child is file `a.txt`

#### Scenario: Single-child directory chain collapses

- **WHEN** expand-all scans `foo/bar/baz.txt` with no siblings
- **THEN** the tree exposes a collapsed directory name containing `foo/bar`
- **AND** `baz.txt` is a child of that collapsed node

### Requirement: Missing path is safe

Scanning a path that does not exist or cannot be listed SHALL NOT raise. The scanner SHALL return a node with empty children or no node, without throwing.

#### Scenario: Absent directory

- **WHEN** the scanner is given a path that does not exist
- **THEN** it returns without error
- **AND** no children are produced for that path

### Requirement: Large-directory scan stays interactive

A one-level scan of a large directory, including building gitignore status from scanned `.gitignore` files, MUST complete within 200 milliseconds on the test machine. “Large” means at least 5000 direct entries plus at least one ignored nested tree of at least 5000 files. The timed path SHALL NOT include numstat git commands. Automated tests MUST fail if that work exceeds that budget.

#### Scenario: Wide directory meets budget

- **WHEN** a temporary directory is created with 5000 files at the top level
- **AND** a one-level scan runs against it, including gitignore annotation
- **THEN** the scan returns within 200 milliseconds
- **AND** the result contains 5000 file children

#### Scenario: Nested ignored tree does not blow the budget

- **WHEN** a temporary directory contains a hidden `node_modules` tree of at least 5000 files plus a modest number of real children
- **AND** a one-level scan runs with ignored names hidden, including gitignore annotation
- **THEN** the scan returns within 200 milliseconds
- **AND** the ignored tree is not present in the result

#### Scenario: Gitignore file does not blow the budget

- **WHEN** a temporary directory contains 5000 top-level files and a `.gitignore` that ignores a subset of them
- **AND** a one-level scan runs including gitignore annotation
- **THEN** the work returns within 200 milliseconds
- **AND** matching files are marked gitignored

### Requirement: Automated unit and performance coverage

The project SHALL ship automated tests that target the filesystem scanner and gitignore annotation directly (no tree UI required for those tests). Unit tests MUST cover ignore, stubs, expand-all, sort, collapse, missing paths, node shape, gitignore matching, nested `.gitignore` files, negation, parent-ignored stubs, grey highlighting of gitignored rows, and `+N-M` formatting for file numstat. Performance tests MUST use disposable fixture trees, enforce the 200 millisecond budget including gitignore annotation, and MUST NOT commit fixtures to the repository. Both SHALL run with the existing headless Lua test command.

#### Scenario: Tests run with the existing suite

- **WHEN** `make test` runs
- **THEN** the scanner unit and performance tests execute as part of that suite
- **AND** they pass against generated fixtures
- **AND** gitignore unit tests execute as part of that suite
- **AND** tests for grey gitignored rows and `+N-M` formatting execute as part of that suite

### Requirement: Gitignore status is derived from scanned gitignore files

After a directory scan, the system SHALL compute gitignore status for scanned paths from `.gitignore` files that appear among those scanned entries. Patterns in a `.gitignore` file SHALL apply to scanned descendants of that file’s directory. The system MUST NOT run `git status` (including porcelain, `--ignored=matching`, or untracked expansion) to produce this information. `.git/info/exclude`, global excludes, and the git index SHALL NOT be required.

#### Scenario: Root gitignore marks a matching file

- **WHEN** a directory contains `.gitignore` with the pattern `*.log` and a file `debug.log`
- **AND** the directory is scanned
- **THEN** `debug.log` is marked gitignored
- **AND** `.gitignore` itself is not marked gitignored unless a pattern matches it

#### Scenario: No gitignore means no gitignore status

- **WHEN** a directory has files but no `.gitignore`
- **AND** the directory is scanned
- **THEN** those files are not marked gitignored

#### Scenario: Works without a git repository

- **WHEN** a temporary directory is not a git repository
- **AND** it contains `.gitignore` with `secret.env` and a file `secret.env`
- **AND** the directory is scanned
- **THEN** `secret.env` is marked gitignored
- **AND** the operation does not fail for lack of git

### Requirement: Nested gitignore files and negation apply to scanned children

A `.gitignore` file in a scanned subdirectory SHALL apply to that subdirectory’s scanned children, in addition to patterns from ancestor `.gitignore` files already seen. A later negation pattern (`!`) SHALL un-ignore a scanned path that an earlier pattern ignored.

#### Scenario: Nested gitignore applies under its directory

- **WHEN** the root `.gitignore` is empty
- **AND** `pkg/.gitignore` contains `dist/`
- **AND** `pkg` is scanned (including its direct children)
- **THEN** `pkg/dist` is marked gitignored
- **AND** a sibling of `dist` under `pkg` is not marked gitignored unless another pattern matches it

#### Scenario: Negation un-ignores a scanned file

- **WHEN** `.gitignore` contains `*.log` then `!keep.log`
- **AND** the directory contains `debug.log` and `keep.log`
- **AND** the directory is scanned
- **THEN** `debug.log` is marked gitignored
- **AND** `keep.log` is not marked gitignored

### Requirement: Parent gitignore marks unpopulated directory stubs

When a scanned `.gitignore` ignores a child directory, that child SHALL be marked gitignored even if it is an unpopulated stub. The system MUST NOT enumerate that stub’s contents in order to mark it.

#### Scenario: Ignored directory stub is marked without descent

- **WHEN** `.gitignore` contains `build/`
- **AND** a one-level scan finds directory `build` as a child
- **THEN** the `build` node is marked gitignored
- **AND** files inside `build` are not listed as a result of that mark

### Requirement: Gitignored files and directories render grey

When a scanned file or directory is marked gitignored and is shown in the tree, the system SHALL highlight its arrow, icon, and name with the ignored (grey) highlight. Name-based skip of `node_modules`, `vendor`, `dist`, `build`, `target`, and `.git` SHALL still hide those names when ignored names are hidden. Gitignored scanned entries SHALL remain listed (grey), not omitted, when they are not also name-based skips.

#### Scenario: Gitignored file is grey

- **WHEN** `.gitignore` contains `secret.env` and that file exists
- **AND** the tree shows that directory
- **THEN** `secret.env` is visible
- **AND** its row uses the ignored grey highlight

#### Scenario: Gitignored directory is grey

- **WHEN** `.gitignore` contains `build/`
- **AND** directory `build` is a scanned child
- **THEN** the `build` row uses the ignored grey highlight

#### Scenario: Name-based skip still hides node_modules

- **WHEN** ignored names are hidden
- **AND** the directory contains `node_modules`
- **THEN** `node_modules` is not shown
- **AND** a gitignored file such as `secret.env` is still shown grey

### Requirement: Gitignore annotation does not use git dump commands

Building gitignore status MUST NOT spawn whole-repo porcelain status, untracked-directory expansion, or `.git` file watchers.

#### Scenario: Annotation does not require git status

- **WHEN** gitignore status is built for a scanned directory that contains a `.gitignore` file
- **THEN** the result is produced without running `git status`

### Requirement: Dirty files show plus-minus line counts

For a shown file that is not gitignored, if staged and unstaged numstat together have added or deleted lines, the tree SHALL append the previous format after the name: ` +N-M` when both are non-zero, ` +N` when only added, ` -M` when only deleted. Additions SHALL use the added highlight and deletions the deleted highlight. Gitignored rows SHALL NOT show these counts.

#### Scenario: File with adds and deletes

- **WHEN** a visible file has numstat added 23 and deleted 23
- **AND** it is not gitignored
- **THEN** the row includes ` +23-23` after the name
- **AND** `+23` uses the added highlight
- **AND** `-23` uses the deleted highlight

#### Scenario: Add-only and delete-only

- **WHEN** a file has only added lines
- **THEN** the row includes ` +N` and not a `-0`
- **WHEN** a file has only deleted lines
- **THEN** the row includes ` -M` and not a `+0`

#### Scenario: Gitignored file has no numstat text

- **WHEN** a file is marked gitignored
- **AND** numstat data exists for that path
- **THEN** the row does not append `+N-M`

### Requirement: Numstat attaches without a filesystem re-scan

Numstat SHALL be fetched asynchronously after the tree is already populated from the filesystem scan. When it arrives, the system SHALL attach counts to existing file nodes and re-render. It MUST NOT re-list directories to apply numstat. A missing git root or a failed git command SHALL leave nodes without counts and MUST NOT fail the scan.

#### Scenario: Tree is usable before numstat returns

- **WHEN** a repository tree is opened
- **THEN** the filesystem listing is shown without waiting for numstat
- **AND** `+N-M` appears on dirty files after numstat arrives without a new directory listing

#### Scenario: Not a git repository

- **WHEN** the tree root is not inside a git repository
- **THEN** the scan still succeeds
- **AND** no `+N-M` text is shown

### Requirement: Files show an A M or D postfix

A shown file that is not gitignored SHALL append a single letter after the name when git reports it as added, modified, or deleted. Mapping: untracked and added → `A`; modified, renamed, or copied → `M`; deleted → `D`. If `+N-M` is also present, the letter SHALL come after that count. Gitignored files SHALL NOT show the letter.

#### Scenario: Modified file

- **WHEN** a visible file is modified in git
- **AND** it is not gitignored
- **THEN** the row includes `M` after the name

#### Scenario: Untracked file is A

- **WHEN** a visible file is untracked
- **THEN** the row includes `A` after the name

#### Scenario: Letter follows plus-minus counts

- **WHEN** a file has numstat `+23-23` and is modified
- **THEN** the row contains ` +23-23` and then `M`

#### Scenario: Gitignored file has no AMD letter

- **WHEN** a file is marked gitignored
- **AND** git would otherwise classify it as modified
- **THEN** the row does not include `A`, `M`, or `D` as a git postfix

### Requirement: Directories show an aggregated DMA summary after the name

A shown directory or root that is not gitignored SHALL append the unique letters from its subtree in canonical order **D** then **M** then **A** (for example `DMA`, `MA`, `D`). Each letter SHALL use the deleted, modified, or added highlight. The summary SHALL include letters from scanned children and from git-deleted paths under that directory even if those files are not listed as tree nodes. Gitignored directories SHALL NOT show a summary.

#### Scenario: Mixed subtree

- **WHEN** a directory has a deleted child, a modified child, and an added child
- **AND** the directory is not gitignored
- **THEN** the row includes `DMA` after the name
- **AND** `D` uses the deleted highlight, `M` the modified highlight, and `A` the added highlight

#### Scenario: Nested roll-up

- **WHEN** directory `src` contains `src/app` whose only dirty file is modified
- **THEN** both `src/app` and `src` include `M` after the name

#### Scenario: Clean directory

- **WHEN** a directory’s subtree has no added, modified, or deleted files
- **THEN** no DMA summary is appended

### Requirement: AMD attaches without a filesystem re-scan

A/M/D data SHALL be applied after the filesystem listing is already shown. When it arrives, the system SHALL stamp existing nodes and re-render. It MUST NOT re-list directories to apply AMD. It MUST NOT run `git status` with `--ignored=matching`. A missing git root or a failed git command SHALL leave nodes without AMD and MUST NOT fail the scan.

#### Scenario: Tree is usable before AMD returns

- **WHEN** a repository tree is opened
- **THEN** the filesystem listing is shown without waiting for AMD letters
- **AND** file postfixes and directory DMA appear after status arrives without a new directory listing

#### Scenario: Not a git repository

- **WHEN** the tree root is not inside a git repository
- **THEN** the scan still succeeds
- **AND** no A/M/D postfix or directory DMA is shown

### Requirement: Add prompt prefills an editable destination path

When adding a node, the prompt SHALL present the destination as editable text, not only a filename under a fixed parent. The default SHALL be the tree-root-relative path of the target directory with a trailing slash. The target directory is the directory under the cursor, or the parent of the file under the cursor.

#### Scenario: Cursor on a directory

- **WHEN** the user adds a node with the cursor on directory `src/app`
- **THEN** the input default is `src/app/`
- **AND** the prompt identifies a new file (for example `New file: `)

#### Scenario: Cursor on a file

- **WHEN** the user adds a node with the cursor on file `src/app/page.tsx`
- **THEN** the input default is `src/app/`

### Requirement: Edited path creates missing directories and the file

The submitted string SHALL be treated as the full destination. Relative paths resolve against the tree root. Absolute paths SHALL be used as given. Missing parent directories MUST be created. A path that does not end with `/` SHALL create an empty file at that location.

#### Scenario: Nested path with new parent dirs

- **WHEN** the default is `src/app/` and the user submits `src/app1/app/index.tsx`
- **THEN** directories `src/app1` and `src/app1/app` are created if missing
- **AND** an empty file `src/app1/app/index.tsx` exists

#### Scenario: Sibling file under the default directory

- **WHEN** the default is `src/app/` and the user submits `src/app/util.ts`
- **THEN** file `src/app/util.ts` is created
- **AND** no extra directories are created beyond those already present

#### Scenario: Absolute destination

- **WHEN** the user submits an absolute path `/tmp/example/foo.txt` whose parents do not all exist
- **THEN** missing parents are created
- **AND** the file exists at that absolute path

### Requirement: Trailing slash creates a directory only

A submitted path that ends with `/` SHALL create that directory (and missing parents) and SHALL NOT create an extra file.

#### Scenario: Directory-only create

- **WHEN** the user submits `src/app1/hooks/`
- **THEN** directory `src/app1/hooks` exists
- **AND** no file named `hooks` is created

### Requirement: Existing paths are not overwritten

If the resolved destination already exists as a file or directory, the system SHALL NOT overwrite it and SHALL notify the user.

#### Scenario: File already exists

- **WHEN** the user submits a path of an existing file
- **THEN** that file’s contents are unchanged
- **AND** a warning is shown

#### Scenario: Empty or cancelled input

- **WHEN** the user cancels or submits an empty string
- **THEN** no files or directories are created

### Requirement: Tree updates after a successful create

After a successful file create, the tree SHALL refresh and reveal the new file, and the file SHALL open in an editor. After a successful directory-only create, the tree SHALL refresh and reveal that directory.

#### Scenario: File create follows into the editor

- **WHEN** a new file is created successfully
- **THEN** the tree shows the new file
- **AND** the file is opened for editing

### Requirement: Empty ancestor directories are removed after delete

After a file or directory is deleted from the tree, the system SHALL remove each ancestor directory of that path whose subtree contains no files, walking upward until a directory that still contains a file or until the tree root. The tree root SHALL NOT be deleted.

#### Scenario: Last file in a nested create chain

- **WHEN** the tree root contains only `src/app1/app/index.tsx` plus other files under `src/` (not under `app1`)
- **AND** the user deletes `src/app1/app/index.tsx`
- **THEN** directories `src/app1/app` and `src/app1` no longer exist
- **AND** `src/` still exists

#### Scenario: Sibling file keeps the parent

- **WHEN** `src/app1/app/` contains `index.tsx` and `util.ts`
- **AND** the user deletes `index.tsx`
- **THEN** `src/app1/app` still exists
- **AND** `util.ts` is unchanged

#### Scenario: Nested empty dirs without files are removed together

- **WHEN** `src/app1/app/hooks/` exists with no files anywhere under `app1`
- **AND** prune starts at `src/app1/app/hooks`
- **THEN** `hooks`, `app`, and `app1` are all removed
- **AND** the tree root is unchanged

### Requirement: Hidden files count as contents

A directory SHALL NOT be pruned if its subtree contains any file, including dotfiles such as `.gitkeep`.

#### Scenario: gitkeep preserves the directory

- **WHEN** `src/empty/.gitkeep` exists
- **AND** prune starts at `src/empty`
- **THEN** `src/empty` still exists
- **AND** `.gitkeep` is unchanged

### Requirement: Empty ancestors are removed after a move out of a directory

After a file or directory is moved to a path outside its old parent, the system SHALL prune empty ancestor directories of the **old** path using the same rules as after delete.

#### Scenario: Move last nested file away

- **WHEN** the only file under `src/app1/` is `src/app1/app/index.tsx`
- **AND** the user moves it to `src/index.tsx`
- **THEN** `src/app1/app` and `src/app1` no longer exist
- **AND** `src/index.tsx` exists

### Requirement: Tree root is never pruned

Prune SHALL stop at the tree root even if the root would otherwise have no files.

#### Scenario: Last file under root

- **WHEN** the only file in the tree is `readme.md` at the root
- **AND** the user deletes `readme.md`
- **THEN** the tree root directory still exists

### Requirement: Tree refreshes after prune

After prune runs as part of delete or move, the tree SHALL refresh so removed directories are not shown.

#### Scenario: Deleted nested file disappears with empty parents

- **WHEN** the user deletes the last file in a nested empty chain
- **THEN** the tree no longer lists those empty directories

### Requirement: Tree window width follows visible indent and names

The tree window width SHALL be the maximum display width of currently visible rows (indent + arrow + icon + name and any git postfix), clamped to a configurable minimum and maximum. Defaults SHALL be 30 and 100 columns. Changing which rows are visible (open, expand, collapse, refresh) SHALL recompute the width while auto-fit is on.

#### Scenario: Short names use the minimum

- **WHEN** every visible row is shorter than 30 columns
- **AND** auto-fit is on
- **THEN** the tree window width is 30

#### Scenario: Medium names auto-size inside the band

- **WHEN** the longest visible row is 45 columns
- **AND** min is 30 and max is 100
- **AND** auto-fit is on
- **THEN** the tree window width is 45

#### Scenario: Deep indent plus long name still auto-fits under the max

- **WHEN** indent and name together are 52 columns
- **AND** auto-fit is on
- **THEN** the window width is 52

### Requirement: Width min and max are configurable

`width_min` and `width_max` SHALL be tree config (defaults 30 and 100). Auto-fit SHALL use those bounds. If min is greater than max, the system SHALL treat them as the same number (no inverted range).

#### Scenario: Custom max

- **WHEN** config sets `width_max` to 80
- **AND** the longest visible row is 70 columns
- **AND** auto-fit is on
- **THEN** the window width is 70

### Requirement: Content longer than max stays capped until the user expands

If the longest visible row is wider than `width_max`, auto-fit SHALL set the window to `width_max` and SHALL NOT grow past it. The user SHALL be able to expand the tree window past the max to fit that content, and to return to auto-fit.

#### Scenario: Over max stays at max

- **WHEN** the longest visible row is 120 columns
- **AND** `width_max` is 100
- **AND** auto-fit is on
- **THEN** the window width is 100

#### Scenario: Manual expand past max

- **WHEN** the longest visible row is 120 columns
- **AND** the user expands the tree window manually
- **THEN** the window is at least as wide as that row

#### Scenario: Return to auto-fit

- **WHEN** the user has expanded past max
- **AND** they restore auto-fit
- **THEN** the window width is again clamped to `[width_min, width_max]`

### Requirement: Tree opens as a filesystem sidebar

The system SHALL provide a filesystem-only file tree as a left sidebar. Toggling the tree SHALL open it when closed and close it when open. `:BSITree` with an optional directory SHALL open a tree at that path, or at the current working directory when omitted. Opening SHALL show the filesystem listing without waiting for git decorations.

#### Scenario: Toggle opens and closes

- **WHEN** the user toggles the tree and it is not open
- **THEN** a left split shows the filesystem listing
- **WHEN** they toggle again
- **THEN** that tree window is closed

#### Scenario: Command opens at a directory

- **WHEN** the user runs `:BSITree` with a directory argument
- **THEN** a tree opens with that directory as root

### Requirement: Git changes view lists porcelain paths only

`<leader>eg` SHALL open the tree on git changes and use that tree as the file panel. The listing SHALL be built from `git status` paths, not a filesystem scan. Directories with a single child directory SHALL collapse the same way as the filesystem tree. The first changed file SHALL open in BsiDiffViewPanel as a side-by-side diff in the current tab, without an extra key. The worktree text SHALL be the left pane and HEAD the right pane, opened on the first change. The panes SHALL stay aligned by the corresponding diff lines. `]c` and `[c` SHALL move between changes in that file. `>` and `<` SHALL resize the diff panes while this view is open. Focus SHALL stay in the tree. `j` and `k` SHALL move to the next or previous changed file and show that file in the same BsiDiffViewPanel windows. `i` in the git tree or in the diff SHALL close that diff, return the tree to the filesystem listing, reveal that file, and show it as the chosen buffer. `q` SHALL close that diff, return the tree to the filesystem listing, and show the buffer that was open before the diff. Pressing `<leader>eg` again SHALL close the tree and those BsiDiffViewPanel windows and SHALL leave the tab open. `<leader>ee` while this view is open SHALL close the panel and the git tree and SHALL show the buffer that was open before the diff. The filesystem toggle SHALL keep listing the filesystem. `D` on a filesystem file SHALL still open that path with Diffview. The legacy git-mode mapping SHALL open or focus the filesystem tree.

#### Scenario: Open git changes

- **WHEN** the user presses `<leader>eg` in a git repository
- **THEN** the tree lists changed files
- **AND** ignored paths are omitted
- **AND** the first changed file is shown in BsiDiffViewPanel with the worktree on the left and HEAD on the right, opened on the first change
- **AND** `j` and `k` move between changed files and update that diff in the same windows
- **AND** `]c` and `[c` move between changes, and `>` and `<` resize the diff panes
- **AND** `i` closes the diff, lists the filesystem in the tree, and shows that file as the chosen buffer
- **AND** `q` closes the diff, lists the filesystem in the tree, and shows the previous buffer
- **AND** `<leader>ee` closes the diff and the git tree and shows the previous buffer

#### Scenario: Legacy git-mode mapping

- **WHEN** the user invokes the legacy git-mode mapping
- **THEN** the filesystem tree opens or is already focused
- **AND** the listing is not limited to git-changed files

### Requirement: Tree window is not an edit target

The tree buffer SHALL be a scratch non-file buffer. The tree window SHALL keep that buffer; an edit or picker MUST NOT replace it in place. Opening a file while the tree is focused SHALL land in a normal editor window.

#### Scenario: File from a picker

- **WHEN** the tree window is focused
- **AND** the user opens a file from a picker
- **THEN** the file opens in an editor window
- **AND** the tree buffer remains in the tree window

#### Scenario: Enter on a file

- **WHEN** the cursor is on a file in the tree
- **AND** the user presses Enter
- **THEN** that file is opened in an editor window
- **AND** the tree window still shows the tree

### Requirement: Current file is revealed and highlighted

When the user enters a real file buffer, open trees SHALL reveal that file if it is under the tree root and SHALL highlight its row. The tree MUST NOT treat its own buffer as the current file.

#### Scenario: Switch to a project file

- **WHEN** a tree is open
- **AND** the user enters a file under the tree root
- **THEN** that file’s row is visible
- **AND** it uses the current-file highlight

### Requirement: Trees refresh without losing expansion

When buffers are added or deleted, open trees SHALL re-render. A manual refresh SHALL re-scan the filesystem and SHALL preserve which directories were expanded.

#### Scenario: Manual refresh keeps expansion

- **WHEN** directories A and B are expanded
- **AND** the user refreshes the tree
- **THEN** the listing is re-scanned
- **AND** A and B remain expanded

### Requirement: Enter toggles directories

Enter on a directory SHALL expand or collapse it. Expanding an unpopulated directory SHALL load its children. Changing expansion SHALL recompute auto-fit width when auto-fit is on.

#### Scenario: Expand a collapsed directory

- **WHEN** the cursor is on a collapsed directory
- **AND** the user presses Enter
- **THEN** that directory’s children become visible

### Requirement: Tree keys yank, open externally, diff, toggle ignored names, and close

While the tree is focused, in normal mode: `Y` SHALL yank the path relative to the tree root; `o` SHALL open the node with the system default application; `D` on a file SHALL open a git diff for that file; `h` SHALL toggle visibility of name-based ignored directories, which SHALL be visible when the tree opens; `q` SHALL close the tree window. Add, rename-move, and delete SHALL use `a`, `r`/`u`, and `d` respectively. `y` copies the file itself, and `c` copies file contents, as specified below.

#### Scenario: Yank relative path

- **WHEN** the cursor is on `src/app/page.tsx` under tree root `/proj`
- **AND** the user presses `Y`
- **THEN** the yanked text is `src/app/page.tsx`

#### Scenario: Toggle ignored names

- **WHEN** ignored names are hidden
- **AND** the directory contains `node_modules`
- **AND** the user presses `h`
- **THEN** `node_modules` becomes visible

#### Scenario: Close

- **WHEN** the tree window is focused
- **AND** the user presses `q`
- **THEN** that tree window is closed

### Requirement: y copies files for paste

`Y` SHALL put the root-relative path on the clipboard registers immediately, so a following paste sees that text.

`y` SHALL stage the file or directory under the cursor as a copy of that filesystem node. In visual mode, `y` SHALL stage each selected file or directory. `x` in normal mode SHALL stage the node under the cursor as a cut. Staging the same paths with the same action SHALL clear the stage. The root MUST NOT be staged. A selected path inside another selected directory MUST NOT be staged separately. Staged names SHALL use the copied or cut highlight.

`p` SHALL paste every staged path into the directory under the cursor, or into the parent directory when the cursor is on a file. A copy SHALL duplicate the file or directory and leave the source in place. A cut SHALL move it and prune empty ancestors of the old path. An existing destination MUST NOT be overwritten; the user is prompted for another path. Pasting a directory into itself MUST NOT proceed.

#### Scenario: Visual yank then paste

- **WHEN** the user visually selects `a.txt` and `b.txt` and presses `y`
- **AND** the user then presses `p` on directory `dest`
- **THEN** `dest/a.txt` and `dest/b.txt` exist with the same contents
- **AND** the original files still exist

#### Scenario: Cut moves and prunes an empty parent

- **WHEN** the user cuts `nested/a.txt` and pastes it on the tree root
- **THEN** `a.txt` exists at the root
- **AND** `nested/a.txt` does not exist
- **AND** `nested` is removed when it no longer contains a file

#### Scenario: Existing destination is kept

- **WHEN** a copy would land on a path that already exists
- **THEN** that existing file is unchanged
- **AND** the user is asked for a different destination

### Requirement: c copies file contents to the paste registers

`c` on a file SHALL put that file’s contents on the paste registers and SHALL NOT open a window. `c` on a directory SHALL put the contents of the files directly inside it on the paste registers, each introduced by its name, and MUST NOT include files nested in subdirectories. In visual mode, `c` SHALL do the same for the selected nodes.

#### Scenario: Copy one file’s contents

- **WHEN** the cursor is on `note.txt` and the user presses `c`
- **THEN** the paste registers hold the contents of `note.txt`
- **AND** no new window is opened

#### Scenario: Copy a directory’s contents

- **WHEN** the cursor is on a directory that contains `a.txt` and `sub/hidden.txt`
- **AND** the user presses `c`
- **THEN** the paste registers include the contents of `a.txt`
- **AND** they do not include the contents of `sub/hidden.txt`

### Requirement: Users can rename or move the node under the cursor

`r` and `u` SHALL prompt to rename or move the node under the cursor. The submitted path SHALL be the destination. After a successful move, empty ancestors of the old path SHALL be pruned. An existing destination MUST NOT be overwritten.

#### Scenario: Rename a file

- **WHEN** the cursor is on `src/old.ts`
- **AND** the user submits `src/new.ts`
- **THEN** the file exists at `src/new.ts`
- **AND** `src/old.ts` does not exist

### Requirement: Users can nudge tree width by three columns

`>` SHALL increase the tree window width by 3 columns, including past `width_max` up to the editor frame. `<` SHALL decrease it by 3 columns and MUST NOT go below `width_min`. After a nudge, auto-fit SHALL stay off until open, expand, collapse, refresh, or revealing the current file restores it.

#### Scenario: Widen past max

- **WHEN** auto-fit width is 100
- **AND** the user presses `>`
- **THEN** the window width is 103

#### Scenario: Narrow not below min

- **WHEN** the window width is 30
- **AND** the user presses `<`
- **THEN** the window width is 30
