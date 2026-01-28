local M = {}

local function normalize_case(case_mode)
  if not case_mode or case_mode == "" then
    return "smart"
  end

  case_mode = case_mode:lower()
  if case_mode == "ignore" or case_mode == "insensitive" or case_mode == "i" then
    return "ignore"
  end
  if case_mode == "sensitive" or case_mode == "s" then
    return "sensitive"
  end
  if case_mode == "smart" or case_mode == "smart-case" then
    return "smart"
  end

  return "smart"
end

local function parse_args(argstr)
  if type(argstr) ~= "string" then
    argstr = ""
  end

  local args = vim.split(argstr, "%s+", { trimempty = true })
  local pattern
  local glob
  local case_mode

  for _, token in ipairs(args) do
    if vim.startswith(token, "--glob=") then
      glob = token:sub(8)
    elseif vim.startswith(token, "--case=") then
      case_mode = token:sub(8)
    elseif not pattern then
      pattern = token
    end
  end

  return {
    pattern = pattern,
    glob = glob,
    case_mode = normalize_case(case_mode),
  }
end

local function build_rg_args(pattern, glob, case_mode)
  local cmd = { "rg", "--vimgrep", "--color=never" }

  if case_mode == "ignore" then
    table.insert(cmd, "-i")
  elseif case_mode == "sensitive" then
    table.insert(cmd, "-s")
  else
    table.insert(cmd, "-S")
  end

  if glob and glob ~= "" then
    table.insert(cmd, "-g")
    table.insert(cmd, glob)
  end

  table.insert(cmd, pattern)
  return cmd
end

local function parse_rg_line(line)
  local file, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.*)$")
  if not file then
    return nil
  end

  return {
    filename = file,
    lnum = tonumber(lnum),
    col = tonumber(col),
    text = text,
  }
end

local function build_lines(items)
  local lines = {}
  local max_width = 0

  for _, item in ipairs(items) do
    local filename = vim.fn.fnamemodify(item.filename, ":.")
    local line = string.format("%s:%d:%d:%s", filename, item.lnum, item.col, item.text)
    table.insert(lines, line)
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end

  return lines, max_width
end

local function window_config(max_width, line_count)
  local width_limit = math.floor(vim.o.columns * 0.8)
  local height_limit = math.floor(vim.o.lines * 0.6)

  local width = math.min(math.max(max_width + 2, 20), math.max(width_limit, 20))
  local height = math.min(math.max(line_count, 1), math.max(height_limit, 5))

  local row = math.max(0, math.floor((vim.o.lines - height) / 2 - 1))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  }
end

local function open_popup(items)
  local lines, max_width = build_lines(items)
  local buf = vim.api.nvim_create_buf(false, true)
  local origin_win = vim.api.nvim_get_current_win()

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "rglist"

  local win = vim.api.nvim_open_win(buf, true, window_config(max_width, #lines))
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].signcolumn = "no"

  local function close_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function open_selection()
    local line = vim.api.nvim_win_get_cursor(win)[1]
    local item = items[line]
    if not item then
      return
    end

    close_win()
    if vim.api.nvim_win_is_valid(origin_win) then
      vim.api.nvim_set_current_win(origin_win)
    end
    vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
    vim.api.nvim_win_set_cursor(0, { item.lnum, math.max(item.col - 1, 0) })
  end

  vim.keymap.set("n", "q", close_win, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close_win, { buffer = buf, silent = true })
  vim.keymap.set("n", "<CR>", open_selection, { buffer = buf, silent = true })
end

function M.run(opts)
  local argstr = opts
  if type(opts) == "table" then
    argstr = opts.args
  end

  local parsed = parse_args(argstr)
  local pattern = parsed.pattern

  if not pattern or pattern == "" then
    pattern = vim.fn.input("Rg pattern: ")
  end

  if not pattern or pattern == "" then
    vim.notify("RgList: pattern required", vim.log.levels.WARN)
    return
  end

  local cmd = build_rg_args(pattern, parsed.glob, parsed.case_mode)
  local stdout = {}
  local stderr = {}

  local job_id = vim.fn.jobstart(cmd, {
    cwd = vim.uv.cwd(),
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stdout, line)
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr, line)
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local items = {}
        for _, line in ipairs(stdout) do
          local entry = parse_rg_line(line)
          if entry then
            table.insert(items, entry)
          end
        end

        if #items > 0 then
          open_popup(items)
          if code ~= 0 and #stderr > 0 then
            vim.notify("RgList error: " .. table.concat(stderr, " "), vim.log.levels.ERROR)
          end
          return
        end

        if code == 1 then
          vim.notify("RgList: no matches", vim.log.levels.INFO)
          return
        end

        if code ~= 0 then
          if #stderr > 0 then
            vim.notify("RgList error: " .. table.concat(stderr, " "), vim.log.levels.ERROR)
          else
            vim.notify("RgList: rg failed (exit " .. code .. ")", vim.log.levels.ERROR)
          end
        end
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify("RgList: failed to start rg", vim.log.levels.ERROR)
  end
end

return M
