local git = require "bsi.git"
local utils = require "bsi.utils"
local M = {}

function M.open_gitlab_pipelines()
  local api_token = os.getenv("GITLAB_API_TOKEN")
  local gitlab_host = os.getenv("GITLAB_HOST")
  local project_name = git.get_gitlab_project_name()
  local branch_name = git.get_current_branch()

  if not api_token then
    vim.notify("GITLAB_API_TOKEN environment variable not set!", vim.log.levels.ERROR)
    return
  end

  if not project_name then
    vim.notify("Unable to determine GitLab project from git remote!", vim.log.levels.ERROR)
    return
  end

  local encoded_project_name = utils.url_encode(project_name)

  local cmd = string.format(
    "curl -s --header 'PRIVATE-TOKEN: %s' 'https://%s/api/v4/projects/%s/pipelines?per_page=10&ref=%s'",
    api_token,
    gitlab_host,
    encoded_project_name,
    branch_name
  )

  local result = vim.fn.system(cmd)
  local pipelines = vim.fn.json_decode(result)

  if not pipelines or vim.tbl_isempty(pipelines) then
    vim.notify("No pipelines found!", vim.log.levels.ERROR)
    return
  end

  local content = { "Pipelines:", "" }

  for _, pipeline in ipairs(pipelines) do
    local line = string.format(
      "Pipeline #%d | Status: %s | Ref: %s | Created At: %s",
      pipeline.id,
      pipeline.status,
      pipeline.ref,
      pipeline.created_at
    )
    table.insert(content, line)
  end

  -- Create floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

  local width = math.floor(vim.o.columns * 0.7)
  local height = #content + 2
  local opts = {
    style = "minimal",
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    border = "rounded",
  }

  vim.api.nvim_open_win(buf, true, opts)
end

return M
