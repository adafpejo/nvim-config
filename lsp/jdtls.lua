---
--- @brief
---
--- https://projects.eclipse.org/projects/eclipse.jdt.ls
---
--- Language server for Java.
---
--- IMPORTANT: If you want all the features jdtls has to offer, [nvim-jdtls](https://github.com/mfussenegger/nvim-jdtls)
--- is highly recommended. If all you need is diagnostics, completion, imports, gotos and formatting and some code actions
--- you can keep reading here.
---
--- For manual installation you can download precompiled binaries from the
--- [official downloads site](http://download.eclipse.org/jdtls/snapshots/?d)
--- and ensure that the `PATH` variable contains the `bin` directory of the extracted archive.
---
--- ```lua
---   -- init.lua
---   vim.lsp.enable('jdtls')
--- ```
---
--- You can also pass extra custom jvm arguments with the JDTLS_JVM_ARGS environment variable as a space separated list of arguments,
--- that will be converted to multiple --jvm-arg=<param> args when passed to the jdtls script. This will allow for example tweaking
--- the jvm arguments or integration with external tools like lombok:
---
--- ```sh
--- export JDTLS_JVM_ARGS="-javaagent:$HOME/.local/share/java/lombok.jar"
--- ```
---
--- For automatic installation you can use the following unofficial installers/launchers under your own risk:
---   - [jdtls-launcher](https://github.com/eruizc-dev/jdtls-launcher) (Includes lombok support by default)
---     ```lua
---       -- init.lua
---       vim.lsp.config('jdtls', { cmd = { 'jdtls' } })
---     ```

local handlers = require 'vim.lsp.handlers'

local env = {
    HOME = vim.uv.os_homedir(),
    XDG_CACHE_HOME = os.getenv 'XDG_CACHE_HOME',
    JDTLS_JVM_ARGS = os.getenv 'JDTLS_JVM_ARGS',
}

local function get_cache_dir()
    return env.XDG_CACHE_HOME and env.XDG_CACHE_HOME or env.HOME .. '/.cache'
end

local function get_jdtls_cache_dir()
    return get_cache_dir() .. '/jdtls'
end

local function get_jdtls_config_dir()
    return get_jdtls_cache_dir() .. '/config'
end

local function get_jdtls_workspace_dir()
    return get_jdtls_cache_dir() .. '/workspace'
end

local function to_jvm_args(src)
    local items = {}

    if type(src) == "string" then
        for s in string.gmatch(src, "%S+") do
            table.insert(items, s)
        end
    elseif type(src) == "table" then
        for _, v in ipairs(src) do
            if type(v) == "string" then
                table.insert(items, v)
            end
        end
    end

    local out = {}
    for _, v in ipairs(items) do
        table.insert(out, string.format("--jvm-arg=%s", v))
    end

    return table.unpack(out)
end

-- TextDocument version is reported as 0, override with nil so that
-- the client doesn't think the document is newer and refuses to update
-- See: https://github.com/eclipse/eclipse.jdt.ls/issues/1695
local function fix_zero_version(workspace_edit)
    if workspace_edit and workspace_edit.documentChanges then
        for _, change in pairs(workspace_edit.documentChanges) do
            local text_document = change.textDocument
            if text_document and text_document.version and text_document.version == 0 then
                text_document.version = nil
            end
        end
    end
    return workspace_edit
end

local function on_textdocument_codeaction(err, actions, ctx)
    for _, action in ipairs(actions) do
        -- TODO: (steelsojka) Handle more than one edit?
        if action.command == 'java.apply.workspaceEdit' then                                                 -- 'action' is Command in java format
            action.edit = fix_zero_version(action.edit or action.arguments[1])
        elseif type(action.command) == 'table' and action.command.command == 'java.apply.workspaceEdit' then -- 'action' is CodeAction in java format
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

-- Non-standard notification that can be used to display progress
local function on_language_status(_, result)
    local command = vim.api.nvim_command
    command 'echohl ModeMsg'
    command(string.format('echo "%s"', result.message))
    command 'echohl None'
end

local jdtls_path = vim.fn.stdpath('data') .. '/mason/packages/jdtls'
local mac_conifg = jdtls_path .. '/config_mac'
local eclipse_jar = jdtls_path .. '/plugins/org.eclipse.equinox.launcher_1.7.0.v20250331-1702.jar'
local lombok_jar = jdtls_path .. '/lombok.jar'

return {
    cmd = {
        vim.fn.expand("~/.local/share/nvim/mason/bin/jdtls"),
        '-configuration',
        get_jdtls_config_dir(),
        '-data',
        get_jdtls_workspace_dir(),
        string.format("--jvm-arg=%s", '-Dlog.protocol=true'),
        string.format("--jvm-arg=%s", '-Dlog.level=ALL'),
        string.format("--jvm-arg=%s", '-Xmx1g'),
        string.format("--jvm-arg=%s", '--add-modules=ALL-SYSTEM'),
        string.format("--jvm-arg=%s", '--add-opens' .. ' ' .. 'java.base/java.util=ALL-UNNAMED'),
        string.format("--jvm-arg=%s", '--add-opens' .. ' ' .. 'java.base/java.lang=ALL-UNNAMED'),
        string.format("--jvm-arg=%s", '-javaagent:' .. lombok_jar),
    },
    -- cmd = {
    --     '/opt/homebrew/opt/sdkman-cli/libexec/candidates/java/21.0.8-tem/bin/java',
    --     "-Declipse.application=org.eclipse.jdt.ls.core.id1",
    --     "-Dosgi.bundles.defaultStartLevel=4",
    --     "-Declipse.product=org.eclipse.jdt.ls.core.product",
    --     '-Dlog.level=ALL',
    --     '-Dlog.protocol=true',
    --     '--add-modules=ALL-SYSTEM',
    --     '--add-opens java.base/java.util=ALL-UNNAMED',
    --     '--add-opens java.base/java.lang=ALL-UNNAMED',
    --     '-Xmx2G',
    --     '-jar' .. eclipse_jar,
    --     '--jvm-arg=-javaagent:' .. lombok_jar,
    --     -- get_jdtls_jvm_args(),
    --     '-configuration' .. mac_conifg,
    --     '-data' .. get_jdtls_workspace_dir(),
    -- },
    filetypes = { 'java' },
    root_markers = {
        -- Multi-module projects
        '.git',
        'build.gradle',
        'build.gradle.kts',
        -- Single-module projects
        'build.xml',           -- Ant
        'pom.xml',             -- Maven
        'settings.gradle',     -- Gradle
        'settings.gradle.kts', -- Gradle
    },
    init_options = {
        workspace = get_jdtls_workspace_dir(),
        jvm_args = {},
        bundlers = {},
        os_config = nil,
    },
    settings = {
        java = {
            rename = {enabled = true},
            references = { includeDecompiledSources = true },
            import = {
                enabled = true,
                generatesMetadataFilesAtProjectRoot = false,
            },
            eclipse = { downloadSources = true },
            maven = { downloadSources = true },
            implementationsCodeLens = { enabled = true },
            referencesCodeLens = { enabled = true },
            inlayHints = { parameterNames = { enabled = "all" } },
            signatureHelp = { enabled = true },
            completion = {
                favoriteStaticMembers = {
                    "org.hamcrest.MatcherAssert.assertThat",
                    "org.hamcrest.Matchers.*",
                    "org.hamcrest.CoreMatchers.*",
                    "org.junit.jupiter.api.Assertions.*",
                    "java.util.Objects.requireNonNull",
                    "java.util.Objects.requireNonNullElse",
                    "org.mockito.Mockito.*",
                },
            },
            configuration = {
                runtimes = {
                    {
                        name = "JavaSE-24",
                        path = "/opt/homebrew/opt/sdkman-cli/libexec/candidates/java/24.0.2-tem",
                    },
                    {
                        name = "JavaSE-21",
                        path = "/opt/homebrew/opt/sdkman-cli/libexec/candidates/java/21.0.8-tem",
                    },
                    {
                        name = "JavaSE-17",
                        path = "/opt/homebrew/opt/sdkman-cli/libexec/candidates/java/17.0.16-tem",
                    },
                },
            },
            project = {
                referencedLibraries = {
                    "lib/**/*.jar",
                },
            },
        },
    },
    handlers = {
        -- Due to an invalid protocol implementation in the jdtls we have to conform these to be spec compliant.
        -- https://github.com/eclipse/eclipse.jdt.ls/issues/376
        ['textDocument/codeAction'] = on_textdocument_codeaction,
        ['textDocument/rename'] = on_textdocument_rename,
        ['workspace/applyEdit'] = on_workspace_applyedit,
        ['language/status'] = vim.schedule_wrap(on_language_status),
    },
}
