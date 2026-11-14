-- Flatten JSON (comments allowed) into `key = value` lines and copy them
-- onto the paste registers. Does not change the buffer.
--
--   :JsonKV        whole buffer
--   :'<,'>JsonKV   visual range
--   <leader>yk     normal: buffer, visual: selection

local M = {}

local IDENT = "^[%a_][%w_]*$"

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function is_array(value)
  return type(value) == "table" and vim.islist(value)
end

--- JSON text for a leaf. `vim.NIL` is JSON null.
local function encode_scalar(value)
  if value == vim.NIL then
    return "null"
  end
  return vim.json.encode(value)
end

--- Bracket form for a key that is not a dotted identifier.
local function quote_key(key)
  return "[" .. vim.json.encode(key) .. "]"
end

local function join_key(prefix, key)
  if key:match(IDENT) then
    if prefix == "" then
      return key
    end
    return prefix .. "." .. key
  end
  local quoted = quote_key(key)
  if prefix == "" then
    return quoted
  end
  return prefix .. quoted
end

local function join_index(prefix, index)
  return prefix .. "[" .. tostring(index) .. "]"
end

local function sorted_keys(object)
  local keys = {}
  for key in pairs(object) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function append_value(lines, prefix, value)
  if value ~= vim.NIL and type(value) == "table" then
    if is_array(value) then
      if #value == 0 then
        lines[#lines + 1] = prefix == "" and "[]" or (prefix .. " = []")
        return
      end
      for i, item in ipairs(value) do
        append_value(lines, join_index(prefix, i - 1), item)
      end
      return
    end

    local keys = sorted_keys(value)
    if #keys == 0 then
      lines[#lines + 1] = prefix == "" and "{}" or (prefix .. " = {}")
      return
    end
    for _, key in ipairs(keys) do
      append_value(lines, join_key(prefix, tostring(key)), value[key])
    end
    return
  end

  local encoded = encode_scalar(value)
  if prefix == "" then
    lines[#lines + 1] = encoded
  else
    lines[#lines + 1] = prefix .. " = " .. encoded
  end
end

--- Flatten a decoded JSON value. Object keys are sorted at each level.
--- Array indexes are 0-based. Empty objects and arrays stay on one line.
---@param value any
---@return string
function M.flatten(value)
  local lines = {}
  append_value(lines, "", value)
  return table.concat(lines, "\n")
end

--- Decode JSON text and flatten it.
--- Comments are ignored. The source text is not changed.
---@param text string
---@return string|nil flat
---@return string|nil err
function M.flatten_text(text)
  if type(text) ~= "string" then
    return nil, "expected JSON text"
  end
  local body = trim(text)
  if body == "" then
    return nil, "empty JSON"
  end
  local ok, value = pcall(vim.json.decode, body, { skip_comments = true })
  if not ok then
    return nil, tostring(value)
  end
  return M.flatten(value)
end

--- Flatten buffer lines and copy the result to the `+` and `"` registers.
---@param line1 integer 1-indexed
---@param line2 integer 1-indexed
---@param bufnr? integer
---@return string|nil flat
function M.squash(line1, line2, bufnr)
  bufnr = bufnr or 0
  if line1 > line2 then
    line1, line2 = line2, line1
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local flat, err = M.flatten_text(table.concat(lines, "\n"))
  if not flat then
    vim.notify("JSON: " .. (err or "decode failed"), vim.log.levels.ERROR)
    return nil
  end
  vim.fn.setreg("+", flat)
  vim.fn.setreg('"', flat)
  local count = select(2, flat:gsub("\n", "\n")) + 1
  vim.notify("Squashed JSON (" .. count .. " lines)", vim.log.levels.INFO)
  return flat
end

--- `:JsonKV` callback. No range squashes the whole buffer.
--- An explicit range squashes those lines.
---@param opts table
---@return string|nil
function M.command(opts)
  local last = vim.api.nvim_buf_line_count(0)
  local line1, line2
  if opts and opts.range and opts.range > 0 then
    line1, line2 = opts.line1, opts.line2
  else
    line1, line2 = 1, last
  end
  return M.squash(line1, line2, 0)
end

return M
