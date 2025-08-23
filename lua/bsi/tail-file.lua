-- lua/float_term.lua
local M = {}

--- Open a floating terminal running any command.
--- @param cmd string|string[]|nil  The command to run. If nil/empty, opens your shell.
--- @param opts table|nil           { width?, height?, border?, title?, cwd?, env? }
function M.open_term_float(cmd, opts)
  opts = opts or {}
  local width  = vim.o.columns
  local height = vim.o.lines

  local win_w = math.max(20, math.ceil(width  * (opts.width  or 0.8)))
  local win_h = math.max(5,  math.ceil(height * (opts.height or 0.8)))
  local row   = math.ceil((height - win_h) / 2 - 1)
  local col   = math.ceil((width  - win_w) / 2)

  -- scratch buffer + floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    style    = 'minimal',
    width    = win_w,
    height   = win_h,
    row      = row,
    col      = col,
    border   = opts.border or 'rounded',
    title    = opts.title or '',
  })

  -- window/buffer opts
  vim.api.nvim_set_option_value('wrap', false, { win = win })
  vim.api.nvim_set_option_value('number', false, { win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win })
  vim.api.nvim_set_option_value('spell', false, { win = win })
  vim.api.nvim_set_option_value('filetype', 'terminal', { buf = buf })

  -- build command (fallback to user shell)
  local cmd_to_run = cmd
  if cmd_to_run == nil or (type(cmd_to_run) == 'string' and cmd_to_run == '')
     or (type(cmd_to_run) == 'table' and vim.tbl_isempty(cmd_to_run)) then
    cmd_to_run = { vim.o.shell }
  end

  -- IMPORTANT: run in the floating buffer: jobstart(..., {term=true}) creates a terminal in the current buffer
  -- (preferred modern approach over termopen).  [oai_citation:1‡Neovim](https://neovim.io/doc/user/terminal.html?utm_source=chatgpt.com)
  local job_id = vim.fn.jobstart(cmd_to_run, {
    term = true,
    cwd  = opts.cwd,
    env  = opts.env,
    height = win_h,  -- helps pty sizing; see :h jobstart-options.  [oai_citation:2‡Neovim](https://neovim.io/doc/user/builtin.html?utm_source=chatgpt.com)
    on_exit = function(_, code, _)
      if code ~= 0 and vim.api.nvim_buf_is_valid(buf) then
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          vim.api.nvim_buf_call(buf, function()
            vim.notify(('Command exited (%d)'):format(code), vim.log.levels.WARN)
          end)
        end)
      end
    end,
  })

  -- close helpers
  vim.keymap.set({'n', 't'}, 'q', '<cmd>close<CR>', { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({'n', 't'}, '<Esc>', '<cmd>close<CR>', { buffer = buf, nowait = true, silent = true })

  -- stop job when the window/buffer goes away
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'WinClosed' }, {
    buffer = buf,
    once = true,
    callback = function()
      if job_id and job_id > 0 then pcall(vim.fn.jobstop, job_id) end
    end,
  })

  vim.cmd("startinsert")
end

--- Tail the Neovim LSP log using the floating terminal above.
--- @param lines integer|nil  how many last lines to show first (default 200)
function M.tail_lsp_log(lines)
  local logpath = vim.lsp.get_log_path()
  local n = tonumber(lines) or 200
  M.open_term_float({ 'tail', '-n', tostring(n), '-F', logpath }, {
    title = ' LSP Log ',
    border = 'rounded',
  })
end

function M.lazy_git()
  M.open_term_float({ 'lazygit' }, {
    title = ' LSP Log ',
    border = 'rounded',
  })
end

vim.api.nvim_create_user_command('K9S', function()
  M.open_term_float({ 'k9s' }, {
    title = 'k9s',
    border = 'rounded',
  })
end, {})

vim.api.nvim_create_user_command('LG', function()
  M.lazy_git()
end, {})

vim.api.nvim_create_user_command('LspLog', function()
  M.tail_lsp_log()
end, {})

return M
