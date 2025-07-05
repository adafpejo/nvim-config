local M = {}

local function split_string(string)
    local lines = {}
    for s in string:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

function M.get_remotes()
    local output = vim.fn.system { 'git', 'remote' }
    local error = vim.v.shell_error
    if error ~= 0 then
        print(output)
        return nil
    end
    return split_string(output)
end

function M.get_current_commit_hash()
    local output = vim.fn.system { 'git', 'rev-parse', 'HEAD' }
    local error = vim.v.shell_error
    if error ~= 0 then
        print(output)
        return nil
    end
    return output:gsub('%s+', '')
end

function M.get_repo_root()
    local output = vim.fn.system { 'git', 'rev-parse', '--show-toplevel' }
    local error = vim.v.shell_error
    if error ~= 0 then
        print(output)
        return nil
    end
    return output:gsub('%s+', '')
end

--- @return string | nil
function M.get_current_branch()
    local output = vim.fn.system { 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }
    local error = vim.v.shell_error
    if error ~= 0 then
        print(output)
        return nil
    end
    return output:gsub('%s+', '')
end

function M.get_remote_origin()
    return M.get_remote_url("origin")
end

function M.convert_origin_to_https(ssh_or_https)
    -- Convert SSH/HTTPS Git URL to GitLab URL
    local remote_url = ssh_or_https:gsub("%.git$", "")          -- Remove .git suffix
    remote_url = remote_url:gsub("git@([^:]+):", "https://%1/") -- Convert SSH to HTTPS
    return remote_url
end

function M.get_remote_url(remote)
    local output = vim.fn.system { 'git', 'remote', 'get-url', remote }
    local error = vim.v.shell_error
    if error ~= 0 then
        print(output)
        return nil
    end
    return output:gsub('%s+', '')
end

--- @param url string
--- @return string | nil
function M.convert_origin_to_project_name(url)
  return url:match("https?://[^/]+/(.+)%.git")
end
function M.get_gitlab_project_name()
    local git_origin = M.get_remote_origin()
    assert(git_origin ~= "", "Not found git origin")

    return M.convert_origin_to_project_name(git_origin)
end

return M
