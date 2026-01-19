local root_files = {
  'settings.gradle', -- Gradle (multi-project)
  'settings.gradle.kts', -- Gradle (multi-project)
  'build.xml', -- Ant
  'pom.xml', -- Maven
  'build.gradle', -- Gradle
  'build.gradle.kts', -- Gradle
}

local jdtls_path = vim.fn.stdpath('data') .. '/mason/packages/jdtls'
local lombok_jar = jdtls_path .. '/lombok.jar'

---@type vim.lsp.Config
return {
  filetypes = { 'kotlin' },
  root_markers = root_files,
  cmd = {
    vim.fn.expand("~/.local/share/nvim/mason/bin/kotlin_language_server"),
    string.format("--jvm-arg=%s", '-javaagent:' .. lombok_jar),
  },
  init_options = {
    -- Enables caching and use project root to store cache data.
    storagePath = vim.fs.root(vim.fn.expand '%:p:h', root_files) --[[@as string]],
  },
}

