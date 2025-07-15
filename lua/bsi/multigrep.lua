local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local make_entry = require "telescope.make_entry"
local conf = require "telescope.config".values

local M = {}

function M.live_multigrep(opts)
  opts = opts or {}
  opts.cwd = opts.cwd or vim.uv.cwd()

  local finder = finders.new_async_job {
    command_generator = function(prompt)
      if not prompt or prompt == "" then
        return nil
      end

      local pieces = vim.split(prompt, "  ")
      local args = { "rg" }
      if pieces[1] then
        table.insert(args, "-e")
        table.insert(args, pieces[1])
      end

      if pieces[2] then
        table.insert(args, "-g")
        table.insert(args, pieces[2])
      end

      ---@diagnostic disable-next-line: deprecated
      return vim.tbl_flatten {
        args,
        { "--color=never", "--no-heading", "--with-filename", "--line-number", "--column", "--smart-case" },
      }
    end,
    entry_maker = make_entry.gen_from_vimgrep(opts),
    cwd = opts.cwd,
  }

  pickers.new(opts, {
    debounce = 100,
    prompt_title = "Multi Grep",
    finder = finder,
    previewer = conf.grep_previewer(opts),
    sorter = require("telescope.sorters").empty(),
  }):find()
end

function M.tsc_no_emit(opts)
  opts = opts or {}

  local default_vimgrep_args = {
    "tsc",          -- The TypeScript compiler command
    "--noEmit",     -- Instructs tsc to only report errors, not emit files
    "--pretty",     -- Formats the output in a human-readable way, often with file/line/column info
    "--project", ".", -- Specifies the tsconfig.json location (current directory)
    -- Crucial flags for Telescope to parse the output correctly
    "--no-heading",
    "--with-filename",
    "--line-number",
    "--column",
    "--", -- Separator to ensure tsc interprets subsequent arguments as file patterns if any
  }

  -- Merge user-provided vimgrep_arguments with defaults, if any
  local vimgrep_args = vim.list_extend(default_vimgrep_args, opts.vimgrep_arguments or {})

  require('telescope.builtin').live_grep({
    prompt_title = opts.prompt_title or 'TypeScript No Emit Diagnostics', -- Custom prompt title
    vimgrep_arguments = vimgrep_args,
    -- You can pass other live_grep options directly here
    -- For example:
    -- cwd = vim.fn.expand('%:p:h'), -- Search in the current buffer's directory
    -- hidden = true,
    -- search_dirs = { "src", "tests" },
    -- ... other options from telescope.builtin.live_grep
  })
end

return M
