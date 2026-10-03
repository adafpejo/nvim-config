local languages = require("languages")

local opts = {
    ensure_installed = {
        "lua-language-server",             -- Lua LSP
        "gopls",                           -- Go LSP
        "zls",                             -- Zig LSP
        "astro-language-server",           -- Astro LSP

        "typescript-language-server",      -- TypeScript LSP
        "html-lsp",                        -- HTML LSP
        "css-lsp",                         -- CSS LSP

        "rust-analyzer",                   -- Rust LSP
        "tailwindcss-language-server",     -- Tailwind CSS LSP

        -- PHP LSP (phpactor preferred over intelephense for most projects)
        "phpactor",
        -- "intelephense",                 -- Alternative PHP LSP (uncomment if needed)

        -- Formatters (for conform.nvim and general use)
        "stylua",
        "goimports",
        -- Note: gofmt comes with Go installation, not managed by Mason
        --
        -- Linters and diagnostics
        "golangci-lint",
        "eslint_d",
        "luacheck",     -- Lua linting
        "prettier",     -- Formatter

        -- Additional useful tools
        "delve",          -- Go debugger
        "shfmt",          -- Shell formatter
        "shellcheck",     -- Shell linter

        -- "rescriptls",
        -- "helm_ls",
        -- "jsonls",
        -- "eslint@4.8.0",
        -- "tailwindcss",
        -- "svelte",
        -- "dockerls",
        -- "prismals",
        -- "terraformls",
        -- -- "graphql",
        -- -- "emmet_ls",
        -- "pyright",

    }
}

if languages.java then
    table.insert(opts.ensure_installed, "jdtls")
end
require("mason").setup(opts)

-- Auto-install ensure_installed tools with better error handling
local mr = require("mason-registry")
local function ensure_installed()
    for _, tool in ipairs(opts.ensure_installed) do
        if mr.has_package(tool) then
            local p = mr.get_package(tool)
            if not p:is_installed() then
                vim.notify("Mason: Installing " .. tool .. "...", vim.log.levels.INFO)
                p:install():once("closed", function()
                    if p:is_installed() then
                        vim.notify("Mason: Successfully installed " .. tool, vim.log.levels.INFO)
                    else
                        vim.notify("Mason: Failed to install " .. tool, vim.log.levels.ERROR)
                    end
                end)
            end
        else
            vim.notify("Mason: Package '" .. tool .. "' not found", vim.log.levels.WARN)
        end
    end
end

if mr.refresh then
    mr.refresh(ensure_installed)
else
    ensure_installed()
end

-- Groovy LS is optional. It installs on the first Groovy buffer when
-- languages.java and languages.groovy are both true.
local groovy_enabled = false
local groovy_installing = false
local groovy_java_warned = false

local function enable_groovyls()
    if groovy_enabled then
        return
    end
    groovy_enabled = true
    vim.schedule(function()
        vim.lsp.enable("groovyls")
    end)
end

local function install_groovy()
    if groovy_enabled or groovy_installing then
        return
    end
    local tool = "groovy-language-server"
    if not mr.has_package(tool) then
        vim.notify("Mason: Package '" .. tool .. "' not found", vim.log.levels.WARN)
        return
    end
    local p = mr.get_package(tool)
    if p:is_installed() then
        enable_groovyls()
        return
    end
    if vim.fn.executable("java") ~= 1 then
        if not groovy_java_warned then
            groovy_java_warned = true
            vim.notify("Mason: skip " .. tool .. " (Java 11+ required)", vim.log.levels.WARN)
        end
        return
    end
    groovy_installing = true
    vim.notify("Mason: Installing " .. tool .. "...", vim.log.levels.INFO)
    p:install():once("closed", function()
        groovy_installing = false
        if p:is_installed() then
            vim.notify("Mason: Successfully installed " .. tool, vim.log.levels.INFO)
            enable_groovyls()
        else
            vim.notify("Mason: Failed to install " .. tool, vim.log.levels.ERROR)
        end
    end)
end

if languages.java and languages.groovy then
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "groovy",
        callback = function()
            if groovy_enabled or groovy_installing then
                return
            end
            if mr.refresh then
                mr.refresh(install_groovy)
            else
                install_groovy()
            end
        end,
    })
end
