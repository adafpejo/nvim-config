-- Language switches.
--
-- Defaults below apply on every machine. Override them in
-- lua/languages.local.lua (gitignored) so each machine can differ.
-- Restart Neovim after changing the local file.
--
--   return {
--       java = false,
--       groovy = false,
--   }
--
-- java
--   true:  nvim-jdtls, neotest-java, Mason jdtls, treesitter java, LSP jdtls
--   false: none of the above are loaded or installed
--
-- groovy
--   Used only when java is true.
--   true:  install groovy-language-server the first time a Groovy buffer opens
--          (Jenkinsfile counts), then start groovyls
--   false: leave Groovy alone

local defaults = {
    java = false,
    groovy = false,
}

local local_config = vim.fn.stdpath("config") .. "/lua/languages.local.lua"

if vim.fn.filereadable(local_config) == 1 then
    local ok, overrides = pcall(dofile, local_config)
    if ok and type(overrides) == "table" then
        return vim.tbl_extend("force", defaults, overrides)
    end
    local err = ok and "languages.local.lua must return a table" or overrides
    vim.notify("languages: " .. tostring(err) .. " (using defaults)", vim.log.levels.WARN)
end

return defaults
