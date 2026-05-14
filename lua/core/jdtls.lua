local handlers = require 'vim.lsp.handlers'

local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')

local function get_jdtls_workspace_dir()
    local cache = os.getenv('XDG_CACHE_HOME') or (vim.uv.os_homedir() .. '/.cache')
    return cache .. '/jdtls/workspace/' .. project_name
end

-- TextDocument version is reported as 0, override with nil so that
-- the client doesn't think the document is newer and refuses to update
-- https://github.com/eclipse/eclipse.jdt.ls/issues/1695
local function fix_zero_version(workspace_edit)
    if workspace_edit and workspace_edit.documentChanges then
        for _, change in pairs(workspace_edit.documentChanges) do
            local td = change.textDocument
            if td and td.version == 0 then
                td.version = nil
            end
        end
    end
    return workspace_edit
end

local function on_textdocument_codeaction(err, actions, ctx)
    for _, action in ipairs(actions) do
        if action.command == 'java.apply.workspaceEdit' then
            action.edit = fix_zero_version(action.edit or action.arguments[1])
        elseif type(action.command) == 'table' and action.command.command == 'java.apply.workspaceEdit' then
            action.edit = fix_zero_version(action.edit or action.command.arguments[1])
        end
    end
    handlers[ctx.method](err, actions, ctx)
end

local function on_textdocument_rename(err, workspace_edit, ctx)
    handlers[ctx.method](err, fix_zero_version(workspace_edit), ctx)
end

local function on_workspace_applyedit(err, workspace_edit, ctx)
    handlers[ctx.method](err, fix_zero_version(workspace_edit), ctx)
end

local function on_language_status(_, result)
    vim.api.nvim_command('echohl ModeMsg')
    vim.api.nvim_command(string.format('echo "%s"', result.message))
    vim.api.nvim_command('echohl None')
end

local jdtls_path  = vim.fn.stdpath('data') .. '/mason/packages/jdtls'
local eclipse_jar = jdtls_path .. '/plugins/org.eclipse.equinox.launcher_1.7.100.v20251111-0406.jar'
local lombok_jar  = jdtls_path .. '/lombok.jar'

local mise_java   = vim.fn.expand('~/.local/share/mise/installs/java')

return {
    cmd = {
        mise_java .. '/temurin-25.0.2+10.0.LTS/bin/java',
        '-cp', 'target/dependency/*:target/classes',
        '-Declipse.application=org.eclipse.jdt.ls.core.id1',
        '-Dosgi.bundles.defaultStartLevel=4',
        '-Declipse.product=org.eclipse.jdt.ls.core.product',
        '-Dlog.protocol=true',
        '-Dlog.level=ALL',
        '-javaagent:' .. lombok_jar,
        '-jar', eclipse_jar,
        '-configuration', jdtls_path .. '/config_mac',
        '-data', get_jdtls_workspace_dir(),
    },

    filetypes = { 'java', 'kotlin' },

    root_markers = {
        '.git',
        'pom.xml',
        'build.gradle',
        'build.gradle.kts',
        'build.xml',
        'settings.gradle',
        'settings.gradle.kts',
    },

    init_options = {
        extendedClientCapabilities = require('jdtls.capabilities'),
    },

    settings = {
        java = {
            rename                  = { enabled = true },
            references              = { includeDecompiledSources = true },
            implementationsCodeLens = { enabled = true },
            referencesCodeLens      = { enabled = true },
            signatureHelp           = { enabled = true },
            inlayHints              = { parameterNames = { enabled = 'all' } },
            eclipse                 = { downloadSources = true },
            maven                   = { downloadSources = true },
            import                  = {
                enabled = true,
                generatesMetadataFilesAtProjectRoot = false,
            },
            completion              = {
                favoriteStaticMembers = {
                    'org.hamcrest.MatcherAssert.assertThat',
                    'org.hamcrest.Matchers.*',
                    'org.hamcrest.CoreMatchers.*',
                    'org.junit.jupiter.api.Assertions.*',
                    'java.util.Objects.requireNonNull',
                    'java.util.Objects.requireNonNullElse',
                    'org.mockito.Mockito.*',
                },
            },
            configuration           = {
                runtimes = {
                    { name = 'JavaSE-25', path = mise_java .. '/temurin-25.0.2+10.0.LTS', default = true },
                    { name = 'JavaSE-21', path = mise_java .. '/temurin-21.0.10+7.0.LTS' },
                    { name = 'JavaSE-17', path = mise_java .. '/temurin-17.0.18+8' },
                },
            },
            project                 = {
                referencedLibraries = {
                    'lib/**/*.jar',
                    'build/classes/kotlin/main/**',   -- Gradle Kotlin output
                    'build/classes/kotlin/test/**',
                    'target/classes/**',
                    lombok_jar
                },
            },
        },
    },

    handlers = {
        ['textDocument/codeAction'] = on_textdocument_codeaction,
        ['textDocument/rename']     = on_textdocument_rename,
        ['workspace/applyEdit']     = on_workspace_applyedit,
        ['language/status']         = vim.schedule_wrap(on_language_status),
        ['textDocument/hover']      = function(err, result, ctx, config)
            vim.notify("I trying!!", vim.log.levels.INFO)
            if result and result.contents then
                local value = type(result.contents) == 'table'
                    and result.contents.value
                    or result.contents

                -- strip jdt:// markdown links → keep label only
                value = value:gsub('%[([^%]]+)%]%(jdt://[^%)]+%)', '%1')
                -- strip any remaining bare jdt:// urls
                value = value:gsub('jdt://[%S]+', '')
                -- collapse 3+ consecutive newlines into 2
                value = value:gsub('\n\n\n+', '\n\n')

                if type(result.contents) == 'table' then
                    result.contents.value = value
                else
                    result.contents = value
                end
            end
            vim.lsp.handlers['textDocument/hover'](err, result, ctx, config)
        end,
    },
}
