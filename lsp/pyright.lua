---@brief
---
--- https://github.com/microsoft/pyright
---
--- `pyright`, a static type checker and language server for python
---
--- Resolves the analysis interpreter in this order, relative to the workspace root:
--- 1. project venv (`./.venv`, `./venv`, `./env`)
--- 2. `VIRTUAL_ENV` if the current Neovim process already has one
--- 3. `mise env` / `mise which python` for that directory (venv + version from mise.toml)
--- 4. `python3` / `python` on PATH
---
--- `python.pythonPath` is the setting Pyright actually uses. `venvPath` is the *parent*
--- of virtualenvs, not the venv itself — `venvpath = "./.venv"` does not work.

local VENV_NAMES = { ".venv", "venv", "env" }

---@param venv_dir string|nil
---@return string|nil
local function python_in_venv(venv_dir)
    if not venv_dir or venv_dir == "" then
        return nil
    end
    local unix = venv_dir .. "/bin/python"
    if vim.fn.executable(unix) == 1 then
        return unix
    end
    return nil
end

---@param root string
---@return string|nil
local function python_in_project_venv(root)
    for _, name in ipairs(VENV_NAMES) do
        local python = python_in_venv(root .. "/" .. name)
        if python then
            return python
        end
    end
    return nil
end

---@return string|nil
local function mise_bin()
    local candidates = {
        vim.fn.exepath("mise"),
        "/opt/homebrew/bin/mise",
        vim.fn.expand("~/.local/bin/mise"),
    }
    for _, path in ipairs(candidates) do
        if path ~= "" and vim.fn.executable(path) == 1 then
            return path
        end
    end
    return nil
end

---@param cmd string[]
---@param cwd string
---@return string|nil
local function cmd_stdout(cmd, cwd)
    local ok, result = pcall(function()
        return vim.system(cmd, { cwd = cwd, text = true, timeout = 3000 }):wait()
    end)
    if not ok or not result or result.code ~= 0 or not result.stdout then
        return nil
    end
    local out = vim.trim(result.stdout)
    if out == "" then
        return nil
    end
    return out
end

--- Interpreter mise would use in `root` (activated venv, then tool python).
---@param root string
---@return string|nil
local function python_from_mise(root)
    local mise = mise_bin()
    if not mise then
        return nil
    end

    local env_json = cmd_stdout({ mise, "env", "--json", "-C", root, "-y" }, root)
    if env_json then
        local decoded, env = pcall(vim.json.decode, env_json)
        if decoded and type(env) == "table" then
            local from_venv = python_in_venv(env.VIRTUAL_ENV)
            if from_venv then
                return from_venv
            end
            if type(env.PATH) == "string" then
                for _, dir in ipairs(vim.split(env.PATH, ":", { plain = true })) do
                    local candidate = dir .. "/python"
                    if vim.fn.executable(candidate) == 1 then
                        return candidate
                    end
                end
            end
        end
    end

    local which = cmd_stdout({ mise, "which", "python", "-C", root }, root)
    if which and vim.fn.executable(which) == 1 then
        return which
    end
    return nil
end

---@param root string
---@return string
local function resolve_python(root)
    return python_in_project_venv(root)
        or python_in_venv(vim.env.VIRTUAL_ENV)
        or python_from_mise(root)
        or vim.fn.exepath("python3")
        or vim.fn.exepath("python")
        or "python3"
end

local function set_python_path(command)
    local path = command.args
    local clients = vim.lsp.get_clients {
        bufnr = vim.api.nvim_get_current_buf(),
        name = "pyright",
    }
    for _, client in ipairs(clients) do
        if client.settings then
            client.settings.python = vim.tbl_deep_extend("force", client.settings.python or {}, { pythonPath = path })
        else
            client.config.settings = vim.tbl_deep_extend("force", client.config.settings or {}, {
                python = { pythonPath = path },
            })
        end
        client:notify("workspace/didChangeConfiguration", { settings = nil })
    end
end

return {
    cmd = {
        vim.fn.expand("~/.local/share/nvim/mason/bin/pyright-langserver"),
        "--stdio",
    },
    filetypes = { "python" },
    root_markers = {
        "pyrightconfig.json",
        "pyproject.toml",
        "setup.py",
        "setup.cfg",
        "requirements.txt",
        "Pipfile",
        "mise.toml",
        ".mise.toml",
        ".python-version",
        ".git",
    },
    settings = {
        pyright = {
            disableTaggedHints = true,
        },
        python = {
            analysis = {
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = "openFilesOnly",
            },
        },
    },
    before_init = function(_, config)
        local root = config.root_dir or vim.uv.cwd()
        config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
            python = { pythonPath = resolve_python(root) },
        })
    end,
    on_attach = function(client, bufnr)
        vim.api.nvim_buf_create_user_command(bufnr, "LspPyrightOrganizeImports", function()
            -- pyright.organizeimports is private (not in capabilities), so exec_cmd refuses it.
            client.request("workspace/executeCommand", {
                command = "pyright.organizeimports",
                arguments = { vim.uri_from_bufnr(bufnr) },
            }, nil, bufnr)
        end, {
            desc = "Organize Imports",
        })
        vim.api.nvim_buf_create_user_command(bufnr, "LspPyrightSetPythonPath", set_python_path, {
            desc = "Reconfigure pyright with the provided python path",
            nargs = 1,
            complete = "file",
        })
    end,
}
