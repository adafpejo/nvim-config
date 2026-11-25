local amd = require("bsi.git.amd")

local M = {}

local function norm_path(p)
  if not p or p == "" then
    return p
  end
  p = vim.fn.fnamemodify(p, ":p")
  p = vim.fn.resolve(p)
  return p:gsub("/+$", "")
end

local function basename(p)
  return p:match("([^/]+)$") or p
end

local function dirname(p)
  return p:match("^(.*)/[^/]+$") or p
end

local function sort_nodes(node)
  local children = node.children
  if not children then
    return
  end
  table.sort(children, function(a, b)
    if a.type ~= b.type then
      return a.type == "directory"
    end
    return a.name:lower() < b.name:lower()
  end)
  for _, child in ipairs(children) do
    sort_nodes(child)
  end
end

local function sync_depth(node, depth)
  node.depth = depth
  for _, child in ipairs(node.children or {}) do
    sync_depth(child, depth + 1)
  end
end

local function collapse(node)
  for _, child in ipairs(node.children or {}) do
    collapse(child)
  end
  if node.type ~= "directory" then
    return
  end
  while #node.children == 1 and node.children[1].type == "directory" do
    local child = node.children[1]
    node.name = node.name .. "/" .. child.name
    node.children = child.children or {}
    node.path = child.path
    node.id = child.id
  end
end

local function is_directory(path)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat and stat.type == "directory"
end

---@param root_path string
---@param status_map table<string, string>|nil
---@return bsi.Node
function M.build(root_path, status_map)
  local root = norm_path(root_path)
  local tree = {
    id = root,
    name = basename(root),
    path = root,
    type = "root",
    depth = 0,
    expanded = true,
    children = {},
  }
  status_map = status_map or {}

  local unique = {}
  for path, xy in pairs(status_map) do
    if type(xy) == "string" and xy:sub(1, 2) ~= "!!" then
      local abs = norm_path(path)
      if abs and abs ~= root and (abs == root or abs:sub(1, #root + 1) == root .. "/") then
        unique[abs] = xy
      end
    end
  end

  local ancestor = {}
  for path in pairs(unique) do
    local parent = dirname(path)
    while parent and parent ~= root and #parent > #root and parent:sub(1, #root + 1) == root .. "/" do
      ancestor[parent] = true
      parent = dirname(parent)
    end
  end

  local by_path = { [root] = tree }

  local function ensure_dir(path, parent)
    local found = by_path[path]
    if found then
      return found
    end
    local node = {
      id = path,
      name = basename(path),
      path = path,
      type = "directory",
      depth = 0,
      expanded = true,
      children = {},
    }
    by_path[path] = node
    parent.children[#parent.children + 1] = node
    return node
  end

  local paths = {}
  for path in pairs(unique) do
    paths[#paths + 1] = path
  end
  table.sort(paths)

  for _, path in ipairs(paths) do
    if not ancestor[path] then
      local parent_path = dirname(path)
      local parent = tree
      if parent_path ~= root then
        local chain = {}
        local cursor = parent_path
        while cursor and cursor ~= root do
          chain[#chain + 1] = cursor
          cursor = dirname(cursor)
        end
        for i = #chain, 1, -1 do
          local dir_path = chain[i]
          local dir_parent = tree
          local above = dirname(dir_path)
          if above ~= root then
            dir_parent = by_path[above] or tree
          end
          parent = ensure_dir(dir_path, dir_parent)
        end
      end
      if is_directory(path) then
        ensure_dir(path, parent)
      else
        local node = {
          id = path,
          name = basename(path),
          path = path,
          type = "file",
          depth = 0,
          expanded = false,
          git_letter = amd.xy_to_letter(unique[path]),
        }
        parent.children[#parent.children + 1] = node
        by_path[path] = node
      end
    end
  end

  sort_nodes(tree)
  collapse(tree)
  sync_depth(tree, 0)
  amd.stamp(tree, unique)
  return tree
end

---@param node bsi.Node
---@param collapsed table<string, boolean>
function M.apply_collapsed(node, collapsed)
  if not collapsed then
    return
  end
  if node.type == "directory" and collapsed[node.path] then
    node.expanded = false
  end
  for _, child in ipairs(node.children or {}) do
    M.apply_collapsed(child, collapsed)
  end
end

---@param start_path string
---@param done fun(root: string|nil, map: table|nil)
function M.fetch(start_path, done)
  if not start_path or start_path == "" then
    vim.schedule(function()
      done(nil, nil)
    end)
    return
  end

  vim.system({ "git", "-C", start_path, "--no-optional-locks", "rev-parse", "--show-toplevel" }, {
    text = true,
    timeout = 4000,
  }, function(obj)
    if not obj or obj.code ~= 0 then
      vim.schedule(function()
        done(nil, nil)
      end)
      return
    end
    local root = norm_path((obj.stdout or ""):gsub("%s+$", ""))
    if not root or root == "" then
      vim.schedule(function()
        done(nil, nil)
      end)
      return
    end
    vim.system(amd.STATUS_CMD, {
      cwd = root,
      text = true,
      timeout = 8000,
    }, function(st)
      if not st or st.code ~= 0 then
        vim.schedule(function()
          done(root, nil)
        end)
        return
      end
      local map = amd.parse_status(st.stdout or "", root)
      vim.schedule(function()
        done(root, map)
      end)
    end)
  end)
end

return M
