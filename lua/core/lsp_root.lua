local M = {}

local mod_cache = nil
local std_lib = nil

local ts_lockfiles = {
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "bun.lockb",
    "bun.lock",
}

local function contains(root, path)
    if type(root) ~= "string" or root == "" or type(path) ~= "string" or path == "" then
        return false
    end
    return vim.fs.relpath(root, path) ~= nil
end

local function reused_root(client_name)
    local clients = vim.lsp.get_clients({ name = client_name })
    if #clients == 0 then
        return nil
    end
    return clients[#clients].config.root_dir
end

local function canon(path)
    return vim.fs.normalize(vim.fs.abspath(path))
end

local function read_text(path)
    local fd = io.open(path, "r")
    if not fd then
        return ""
    end
    local text = fd:read("*a") or ""
    fd:close()
    return text
end

local function strip_go_comments(text)
    local out = {}
    local i = 1
    local n = #text
    while i <= n do
        local two = text:sub(i, i + 1)
        local c = text:sub(i, i)
        if c == '"' or c == "`" then
            local j = i + 1
            if c == '"' then
                while j <= n do
                    if text:sub(j, j) == "\\" then
                        j = j + 2
                    elseif text:sub(j, j) == '"' then
                        j = j + 1
                        break
                    else
                        j = j + 1
                    end
                end
            else
                local close = text:find("`", j, true)
                j = close and close + 1 or n + 1
            end
            out[#out + 1] = text:sub(i, j - 1)
            i = j
        elseif two == "//" then
            local nl = text:find("\n", i, true) or (n + 1)
            i = nl
        elseif two == "/*" then
            local close = text:find("*/", i + 2, true)
            local chunk = text:sub(i + 2, close and close - 1 or n)
            local newlines = chunk:gsub("[^\n]", "")
            out[#out + 1] = newlines ~= "" and newlines or " "
            i = close and close + 2 or n + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

local function unquote(token)
    token = vim.trim(token)
    if #token >= 2 and token:sub(1, 1) == '"' and token:sub(-1) == '"' then
        return (token:sub(2, -2):gsub('\\(["\\])', "%1"))
    end
    if #token >= 2 and token:sub(1, 1) == "`" and token:sub(-1) == "`" then
        return token:sub(2, -2)
    end
    return token
end

local function resolve_use(work_dir, token)
    token = unquote(token)
    if token == "" or token == "(" or token == ")" then
        return nil
    end
    if vim.startswith(token, "/") then
        return canon(token)
    end
    return canon(vim.fs.joinpath(work_dir, token))
end

local function use_dirs(work_file)
    local work_dir = vim.fs.dirname(work_file)
    local dirs = {}
    local seen = {}
    local in_block = false

    local function add(token)
        local path = resolve_use(work_dir, token)
        if path and not seen[path] then
            seen[path] = true
            dirs[#dirs + 1] = path
        end
    end

    for line in (strip_go_comments(read_text(work_file)) .. "\n"):gmatch("(.-)\n") do
        local trimmed = vim.trim(line)
        if in_block then
            if trimmed == ")" then
                in_block = false
            else
                add(trimmed)
            end
        elseif trimmed:match("^use%s*%(.*%)%s*$") then
            local body = trimmed:match("^use%s*%((.*)%)%s*$") or ""
            for token in body:gmatch("%S+") do
                add(token)
            end
        elseif trimmed:match("^use%s*%(") then
            in_block = true
            local inline = trimmed:match("^use%s*%((.+)$")
            if inline then
                add(inline)
            end
        else
            local path = trimmed:match("^use%s+(.+)$")
            if path then
                add(path)
            end
        end
    end

    return dirs
end

local function work_includes_module(work_file, mod_dir)
    if not mod_dir then
        return false
    end
    local mod = canon(mod_dir)
    for _, dir in ipairs(use_dirs(work_file)) do
        if dir == mod then
            return true
        end
    end
    return false
end

local function is_work_buffer(fname, work_file)
    local base = fname:match("([^/]+)$")
    if base ~= "go.work" and base ~= "go.work.sum" then
        return false
    end
    return canon(vim.fs.dirname(fname)) == canon(vim.fs.dirname(work_file))
end

local function nearest_work_file(fname)
    local dir = canon(fname)
    local stat = vim.uv.fs_stat(dir)
    if not (stat and stat.type == "directory") then
        dir = canon(vim.fs.dirname(fname))
    end

    local function at(directory)
        local work = vim.fs.joinpath(directory, "go.work")
        if vim.uv.fs_stat(work) then
            return work
        end
    end

    local found = at(dir)
    if found then
        return found
    end
    for parent in vim.fs.parents(dir) do
        found = at(parent)
        if found then
            return found
        end
    end
end

local function gowork_mode(value)
    if value == nil then
        value = vim.env.GOWORK
    end
    if value == nil or value == "" or value == "auto" then
        return "search"
    end
    if value == "off" then
        return "off"
    end
    local path = canon(value)
    if vim.startswith(path, "/") then
        return "file", path
    end
    return "search"
end

local function workspace_dir(fname, mod_dir, gowork)
    local mode, file = gowork_mode(gowork)
    if mode == "off" then
        return nil
    end
    if mode == "file" then
        if file and vim.uv.fs_stat(file) and (work_includes_module(file, mod_dir) or is_work_buffer(fname, file)) then
            return canon(vim.fs.dirname(file))
        end
        return nil
    end

    local work = nearest_work_file(fname)
    if work and (work_includes_module(work, mod_dir) or is_work_buffer(fname, work)) then
        return canon(vim.fs.dirname(work))
    end
end

local function go_env(key, child, done)
    vim.system({ "go", "env", key }, { text = true }, function(output)
        local dir = vim.trim(output.stdout or "")
        if output.code == 0 and dir ~= "" then
            if child then
                dir = vim.fs.joinpath(dir, child)
            end
            done(vim.fs.normalize(dir))
            return
        end
        vim.schedule(function()
            vim.notify(
                ("[gopls] go env %s failed with code %d: %s"):format(key, output.code, output.stderr or ""),
                vim.log.levels.WARN
            )
        end)
        done("")
    end)
end

function M.go_root(fname, opts)
    opts = opts or {}
    if (contains(opts.mod_cache, fname) or contains(opts.std_lib, fname)) and opts.reused_root then
        return opts.reused_root
    end
    local mod_dir = vim.fs.root(fname, "go.mod")
    return workspace_dir(fname, mod_dir, opts.gowork) or mod_dir or vim.fs.root(fname, ".git")
end

function M.go_root_dir(client_name)
    return function(bufnr, on_dir)
        local fname = vim.api.nvim_buf_get_name(bufnr)
        local function finish()
            on_dir(M.go_root(fname, {
                mod_cache = mod_cache,
                std_lib = std_lib,
                reused_root = reused_root(client_name),
            }))
        end

        if mod_cache ~= nil and std_lib ~= nil then
            finish()
            return
        end

        local pending = 0
        local function step()
            pending = pending - 1
            if pending == 0 then
                finish()
            end
        end

        if mod_cache == nil then
            pending = pending + 1
            go_env("GOMODCACHE", nil, function(dir)
                mod_cache = dir
                step()
            end)
        end

        if std_lib == nil then
            pending = pending + 1
            go_env("GOROOT", "src", function(dir)
                std_lib = dir
                step()
            end)
        end
    end
end

function M.typescript_root(fname)
    local project_root = vim.fs.root(fname, { ts_lockfiles, { ".git" } })
    local deno_root = vim.fs.root(fname, { "deno.json", "deno.jsonc" })
    local deno_lock_root = vim.fs.root(fname, { "deno.lock" })
    if deno_lock_root and (not project_root or #deno_lock_root > #project_root) then
        return nil, false
    end
    if deno_root and (not project_root or #deno_root >= #project_root) then
        return nil, false
    end
    return project_root, true
end

function M.typescript_root_dir(bufnr, on_dir)
    local root, activate = M.typescript_root(vim.api.nvim_buf_get_name(bufnr))
    if not activate then
        return
    end
    on_dir(root or vim.fn.getcwd())
end

return M
