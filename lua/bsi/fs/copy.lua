-- lua/bsi/fs/copy.lua
-- Copy a file, symlink, or directory tree. Never overwrites a destination.

local uv = vim.uv or vim.loop

-- UV_FS_COPYFILE_EXCL: fail if the destination already exists.
local COPY_EXCL = 1

local function normalize(p)
  return vim.fs.normalize(p or ""):gsub("/$", "")
end

--- True when `child` is `parent` or a path inside it.
---@param parent string
---@param child string
---@return boolean
local function contains(parent, child)
  parent = normalize(parent)
  child = normalize(child)
  if parent == "" or child == "" then
    return false
  end
  return child == parent or child:sub(1, #parent + 1) == parent .. "/"
end

---@param src string
---@param dst string
---@param lst table
---@return boolean ok
---@return string|nil err
local function copy_entry(src, dst, lst)
  if lst.type == "link" then
    local target, read_err = uv.fs_readlink(src)
    if not target then
      return false, read_err or "readlink failed"
    end
    local ok, link_err = uv.fs_symlink(target, dst)
    if not ok then
      return false, link_err or "symlink failed"
    end
    return true
  end

  if lst.type == "file" then
    local ok, copy_err = uv.fs_copyfile(src, dst, COPY_EXCL)
    if not ok then
      return false, copy_err or "copy failed"
    end
    return true
  end

  if lst.type == "directory" then
    local mode = 493
    if lst.mode then
      mode = lst.mode % 512
      if mode == 0 then
        mode = 493
      end
    end
    local ok, mkdir_err = uv.fs_mkdir(dst, mode)
    if not ok then
      return false, mkdir_err or "mkdir failed"
    end

    local handle = uv.fs_scandir(src)
    if not handle then
      return false, "cannot read directory"
    end
    while true do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local child_src = src .. "/" .. name
      local child_dst = dst .. "/" .. name
      local child_lst, stat_err = uv.fs_lstat(child_src)
      if not child_lst then
        return false, stat_err or "missing child"
      end
      local child_ok, child_err = copy_entry(child_src, child_dst, child_lst)
      if not child_ok then
        return false, child_err
      end
    end
    return true
  end

  return false, "unsupported file type: " .. tostring(lst.type)
end

---@class bsi.fs.CopyResult
---@field ok boolean
---@field path string|nil
---@field kind "file"|"dir"|"link"|"exists"|"missing"|"invalid"
---@field err string|nil

--- Copy `src` to `dst`.
--- A directory is copied recursively. Symlinks are copied as symlinks.
--- An existing destination is left untouched.
---@param src string
---@param dst string
---@return bsi.fs.CopyResult
local function copy(src, dst)
  src = normalize(src)
  dst = normalize(dst)
  if src == "" or dst == "" then
    return { ok = false, kind = "invalid", err = "empty path" }
  end

  local lst, stat_err = uv.fs_lstat(src)
  if not lst then
    return { ok = false, path = dst, kind = "missing", err = stat_err or "missing" }
  end

  if lst.type == "directory" and contains(src, dst) then
    return { ok = false, path = dst, kind = "invalid", err = "cannot copy a directory into itself" }
  end

  if uv.fs_lstat(dst) then
    return { ok = false, path = dst, kind = "exists", err = "already exists" }
  end

  local ok, err = copy_entry(src, dst, lst)
  if not ok then
    if lst.type == "directory" and uv.fs_lstat(dst) then
      vim.fn.delete(dst, "rf")
    end
    return { ok = false, path = dst, kind = "invalid", err = err or "copy failed" }
  end

  local kind = "file"
  if lst.type == "directory" then
    kind = "dir"
  elseif lst.type == "link" then
    kind = "link"
  end
  return { ok = true, path = dst, kind = kind }
end

return setmetatable({
  contains = contains,
}, {
  __call = function(_, src, dst)
    return copy(src, dst)
  end,
})
