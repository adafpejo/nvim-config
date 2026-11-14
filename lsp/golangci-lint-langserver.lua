return {
    cmd = { 'golangci-lint-langserver' },
    filetypes = { 'go', 'gomod', 'gowork', 'gotmpl', 'gosum' },
    root_dir = require("core.lsp_root").go_root_dir("golangci-lint-langserver"),
    init_options = {
        command = { "golangci-lint", "run", "--output.json.path", "stdout", "--show-stats=false", "--issues-exit-code=1" },
    }
}

