local git = require("bsi.git")
local dx = require("bsi.dx")

local M = {}

local function split_remote_url(remote_url)
    local pattern = 'http[s]+://([%w%p]+)/([%w%p]+)/([%w%p]+)'
    local base, user, repo = string.match(remote_url, pattern)
    if not base then
        print('pattern did not match')
        return nil
    end
    return base, user, repo
end

local function build_base_url_to_current_file(base, user, repo, branch, relative_path, line)
    local url = nil
    if string.find(base, 'github') then
        url = string.format('https://%s/%s/%s/blob/%s/%s', base, user, repo, branch, relative_path)
    else
        url = string.format('https://%s/%s/%s/-/blob/%s/%s', base, user, repo, branch, relative_path)
    end
    if line then
        return string.format('%s#L%d', url, line)
    end
    return url
end


local function get_relative_file_path(repo_root)
    local current = vim.api.nvim_buf_get_name(0):gsub("%s+", "")
    local s, e = string.find(current, repo_root, 1, true)
    if s ~= 1 then
        print("Repo root is not a prefix")
        return nil
    end
    local removed = current:sub(e + 2)
    return removed
end

local function get_current_line()
    local r, _ = unpack(vim.api.nvim_win_get_cursor(0))
    return r
end

local function get_url(with_line)
    local remote = git.get_remote_origin()
    if not remote then
        return nil
    end
    local remote_url = git.convert_origin_to_https(remote)
    local base, user, repo = split_remote_url(remote_url)
    if not base then
        return nil
    end
    local url_to_current_file = build_base_url_to_current_file(
        base,
        user,
        repo,
        git.get_current_branch(),
        get_relative_file_path(git.get_repo_root()),
        (with_line and get_current_line() or nil)
    )
    if not url_to_current_file then
        return nil
    end
    return url_to_current_file
end

local function yank_to_register(register, url)
    local cmd = string.format('let @%s = "%s"', register, url)
    vim.cmd(cmd)
    print(url, "yanked to register '" .. register .. "'")
end

M.open_file_in_browser = function()
    dx.open_url(get_url(false))
end
M.open_line_in_browser = function()
    dx.open_url(get_url(true))
end
M.yank_file_url = function(register)
    return yank_to_register(register, get_url(false))
end
M.yank_line_url = function(register)
    return yank_to_register(register, get_url(true))
end
M.get_file_url = function()
    return get_url(false)
end
M.get_line_url = function()
    return get_url(true)
end

return M
