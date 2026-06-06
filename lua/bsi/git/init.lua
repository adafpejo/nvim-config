local M = {}

-- Remote string handling (parsing, conversion, forge classification, blob URL style)
-- lives in a dedicated submodule. This keeps the main git module focused on
-- actually executing git commands and higher-level repo operations.
M.remote = require("bsi.git.remote")

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

function M.get_base_commit()
    local output = vim.fn.system { 'git', 'symbolic-ref', 'refs/remotes/origin/HEAD' }
    local error = vim.v.shell_error
    local default_ref = nil
    if error == 0 then
        default_ref = output:gsub('%s+', ''):gsub('^refs/remotes/origin/', 'origin/')
    end

    local candidates = {}
    if default_ref and default_ref ~= '' then
        table.insert(candidates, default_ref)
    end
    for _, ref in ipairs({ 'origin/main', 'origin/master', 'main', 'master' }) do
        table.insert(candidates, ref)
    end

    local base_ref = nil
    for _, ref in ipairs(candidates) do
        local check = vim.fn.system { 'git', 'rev-parse', '--verify', ref }
        if vim.v.shell_error == 0 then
            base_ref = ref
            break
        end
    end

    if not base_ref then
        return nil
    end

    local merge_base = vim.fn.system { 'git', 'merge-base', 'HEAD', base_ref }
    if vim.v.shell_error ~= 0 then
        print(merge_base)
        return nil
    end
    return merge_base:gsub('%s+', '')
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

function M.get_current_branch()
    local output = vim.fn.system { 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }
    local error = vim.v.shell_error
    if error ~= 0 then
        return nil, output
    else
        return output:gsub('%s+', ''), nil
    end
end

function M.get_remote_origin()
    return M.get_remote_url("origin")
end

-- Re-export from the dedicated remote submodule for backward compatibility.
-- New code is encouraged to use git.remote.convert_remote_to_https directly.
M.convert_remote_to_https = M.remote.convert_remote_to_https
M.convert_origin_to_https = M.remote.convert_origin_to_https
M.convert_origin_to_project_name = M.remote.convert_origin_to_project_name

-- Note: the implementations now live in lua/bsi/git/remote.lua
-- (kept here as thin re-exports so existing call sites do not break).

function M.get_remote_url(remote)
    local output = vim.fn.system { 'git', 'remote', 'get-url', remote }
    local error = vim.v.shell_error
    if error ~= 0 then
        return nil, output
    else
        return output:gsub('%s+', ''), nil
    end
end

function M.get_gitlab_project_name()
    local git_origin = M.get_remote_origin()
    assert(git_origin ~= "", "Not found git origin")

    return M.remote.convert_origin_to_project_name(git_origin)
end

-- Re-export / delegate to the remote submodule.
-- The real classification + blob style logic lives in bsi.git.remote.
M.get_git_provider = M.remote.get_git_provider

-- Convenience re-export of the blob path style helper.
M.get_blob_path_style = M.remote.get_blob_path_style
M.parse_remote = M.remote.parse
M.parse_remote_or_nil = M.remote.parse_or_nil

-- Assuming git module has or needs these helpers:
-- git.get_blame_commit_hash(file_path, line_number)
-- Implementation example (add to git.lua or similar):
function M.get_blame_commit_hash(file_path, line_number)
    local cmd = string.format('git blame -L %d,%d --porcelain "%s"', line_number, line_number, vim.fn.fnameescape(file_path))
    local output = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then return nil end
    -- Parse the first line for the commit hash (e.g., "da39a3e Committer...")
    local first_line = output:match("([0-9a-f]+)")
    return first_line
end

function M.is_file_tracked(file_path)
    local cmd = string.format('git ls-files --error-unmatch "%s"', vim.fn.fnameescape(file_path))
    local output = vim.fn.system(cmd)
    return vim.v.shell_error == 0
end

function M.get_current_line_commits(file_path, line_number)
    local cmd = string.format('git log --oneline --follow -L %d,%d "%s"', line_number, line_number, file_path)
    local output = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then return nil end
    local lines = {}
    for s in output:gmatch("[^\r\n]+") do
        table.insert(lines, s)
    end
    return lines
end

return M
