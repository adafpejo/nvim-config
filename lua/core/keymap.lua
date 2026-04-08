local nvim    = require("bsi.utils.nvim")
local git     = require("bsi.git")

local keymap = vim.keymap
local gitsigns = require('gitsigns')

vim.keymap.set('n', '<leader>hs', gitsigns.stage_hunk)
vim.keymap.set('n', '<leader>hr', gitsigns.reset_hunk)
vim.keymap.set('v', '<leader>hs', function() gitsigns.stage_hunk { vim.fn.line('.'), vim.fn.line('v') } end)
vim.keymap.set('v', '<leader>hr', function() gitsigns.reset_hunk { vim.fn.line('.'), vim.fn.line('v') } end)
vim.keymap.set('n', '<leader>hS', gitsigns.stage_buffer)
vim.keymap.set('n', '<leader>gs', function()
    local file_path = nvim.get_file_path()
    local line_number = nvim.get_cursor_line_number()

    local repo_root = git.get_repo_root()
    assert(repo_root and #repo_root > 0, "Failed to get repo root")

    -- Ensure file is tracked in git
    assert(git.is_file_tracked(file_path), "File is not tracked in git")

    local commit_hash = git.get_blame_commit_hash(file_path, line_number)
    assert(commit_hash and #commit_hash > 0, "Failed to get blame commit hash")

    gitsigns.show_commit(commit_hash, 'tabnew')
end)
vim.keymap.set('n', '<leader>gl', function()
    local file_path = nvim.get_file_path()
    local line_number = nvim.get_cursor_line_number()

    local repo_root = git.get_repo_root()
    assert(repo_root and #repo_root > 0, "Failed to get repo root")

    -- Ensure file is tracked in git
    assert(git.is_file_tracked(file_path), "File is not tracked in git")

    local commits = git.get_current_line_commits(file_path, line_number)
    if not commits or #commits == 0 then
        vim.cmd("echo 'No commits found for this line'")
        return
    end

    -- Show commits in a new buffer with keymaps
    vim.cmd("enew")
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
    vim.api.nvim_buf_set_lines(0, 0, -1, false, commits)

    -- Keymap to select commit on Enter
    vim.keymap.set('n', '<CR>', function()
        local line = vim.api.nvim_get_current_line()
        local commit_hash = line:match("^(%S+)")
        if commit_hash then
            gitsigns.show_commit(commit_hash, 'tabnew')
        end
    end, { buffer = true })

    vim.cmd("wincmd L | vertical resize 50") -- Open as vertical split on the right, resize to 50 columns
end)
vim.keymap.set('n', '<leader>gd', function()
    -- local commit_hash = git.get_current_commit_hash()
    -- assert(commit_hash and #commit_hash > 0, "Failed to get blame commit hash")
    local base_commit = git.get_base_commit()

    vim.cmd("DiffviewOpen " .. base_commit .. "..HEAD")
end)
vim.keymap.set('n', '<leader>hu', gitsigns.undo_stage_hunk)
vim.keymap.set('n', '<leader>hR', gitsigns.reset_buffer)
vim.keymap.set('n', '<leader>th', gitsigns.preview_hunk)
vim.keymap.set('n', '<leader>hb', function() gitsigns.blame_line { full = true } end)
vim.keymap.set('n', '<leader>tb', gitsigns.toggle_current_line_blame)
vim.keymap.set('n', '<leader>hd', gitsigns.diffthis)
vim.keymap.set('n', '<leader>hD', function() gitsigns.diffthis('~') end)
vim.keymap.set('n', '<leader>td', gitsigns.toggle_deleted)

-- nvim-tree keymap
local nt_api = require("nvim-tree.api")
vim.keymap.set("n", "<leader>ee", function()
    nt_api.tree.toggle({ find_file = true })
end, { noremap = true, desc = "NvimTreeToggle" })

-- telescope keymap
-- set keymaps
vim.keymap.set("n", "<leader><leader>", "<cmd>Telescope find_files<cr>", { noremap = true, desc = "Fuzzy find files in cwd" })
vim.keymap.set("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Fuzzy find recent files" })
vim.keymap.set("n", "<leader>fs", "<cmd>Telescope live_grep<cr>", { desc = "Find string in cwd" })
vim.keymap.set("n", "<leader>p", "<cmd>Telescope projects<cr>", { desc = "Projects list" })
vim.keymap.set("n", "<leader>fg", ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>",
    { desc = "Find string in cwd" })
vim.keymap.set("n", "<leader>fw", function()
    local word = nvim.get_cursor_word()

    require("telescope.builtin").live_grep({
        default_text = word,
    })

    local timer = vim.loop.new_timer()

    -- timeout to wait telescope result
    timer:start(
        50,
        0,
        vim.schedule_wrap(function()
            vim.cmd("stopinsert")
        end)
    )
end, { desc = "Find string in cwd" })
vim.keymap.set(
    "n",
    "<leader>fc",
    "<cmd>Telescope grep_string<cr>",
    { desc = "Find string under cursor in cwd" }
)

-- test keymap

keymap.set("n", "<leader>tS", function()
  require("neotest").run.run({ suite = true })
end, { desc = "Run all tests in suite" })
keymap.set("n", "<leader>tt", function()
  require("neotest").run.run(vim.fn.expand("%"))
end, { desc = "Run File" })
keymap.set("n", "<leader>tu", function()
  require("neotest").run.run({ path = vim.fn.expand("%"), extra_args = { "-u" } })
end, { desc = "Run File (-u)" })
keymap.set("n", "<leader>tT", function()
  require("neotest").run.run(vim.loop.cwd())
end, { desc = "Run All Test Files" })
keymap.set("n", "<leader>tr", function()
  require("neotest").run.run()
end, { desc = "Run Nearest" })
keymap.set("n", "<leader>tl", function()
  require("neotest").run.run_last()
end, { desc = "Run Last" })
keymap.set("n", "<leader>ts", function()
  require("neotest").summary.toggle()
end, { desc = "Toggle Summary" })
keymap.set("n", "<leader>to", function()
  require("neotest").output.open({ enter = true, auto_close = true })
end, { desc = "Show Output" })
keymap.set("n", "<leader>tO", function()
  require("neotest").output_panel.toggle()
end, { desc = "Toggle Output Panel" })
keymap.set("n", "<leader>tx", function()
  require("neotest").run.stop()
end, { desc = "Stop" })

keymap.set("n", "<leader>tc", "<cmd>Coverage<cr>", { desc = "Coverage in gutter" })
keymap.set("n", "<leader>tC", "<cmd>CoverageLoad<cr><cmd>CoverageSummary<cr>", { desc = "Coverage summary" })

-- linter/formatter keymap
keymap.set({ "n", "v" }, "<leader>cf", function()
  require("conform").format({ async = true }, function(err, did_edit)
    if not err and did_edit then
      vim.notify("Code formatted", vim.log.levels.INFO, { title = "Conform" })
    end
  end)
end, { desc = "Format buffer" })

