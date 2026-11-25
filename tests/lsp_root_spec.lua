local lsp_root = require("core.lsp_root")

local function mkdir(path)
    vim.fn.mkdir(path, "p")
end

local function write_file(path, contents)
    mkdir(vim.fn.fnamemodify(path, ":h"))
    local fd = assert(io.open(path, "w"))
    fd:write(contents)
    fd:close()
end

local function touch(path)
    write_file(path, "")
end

local function abs(path)
    return vim.fs.abspath(path)
end

describe("lsp root", function()
    local tmp
    local saved_gowork

    before_each(function()
        tmp = vim.fn.tempname()
        mkdir(tmp)
        saved_gowork = vim.env.GOWORK
        vim.env.GOWORK = ""
    end)

    after_each(function()
        vim.env.GOWORK = saved_gowork
        if tmp then
            vim.fn.delete(tmp, "rf")
            tmp = nil
        end
    end)

    describe("go", function()
        it("uses one go.work root for the modules it lists", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse (\n\t./services/api\n\t./services/worker\n)\n")
            touch(tmp .. "/services/api/go.mod")
            touch(tmp .. "/services/api/main.go")
            touch(tmp .. "/services/worker/go.mod")
            touch(tmp .. "/services/worker/main.go")
            local api = lsp_root.go_root(tmp .. "/services/api/main.go")
            local worker = lsp_root.go_root(tmp .. "/services/worker/main.go")
            assert.equals(abs(tmp), api)
            assert.equals(api, worker)
        end)

        it("keeps a module that the go.work does not list", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse ./services/api\n// use ./services/other\n")
            touch(tmp .. "/services/api/go.mod")
            touch(tmp .. "/services/api/main.go")
            touch(tmp .. "/services/other/go.mod")
            touch(tmp .. "/services/other/main.go")
            assert.equals(abs(tmp), lsp_root.go_root(tmp .. "/services/api/main.go"))
            assert.equals(abs(tmp .. "/services/other"), lsp_root.go_root(tmp .. "/services/other/main.go"))
        end)

        it("lets a nearer go.work shadow the parent workspace", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse (\n\t./team/a\n\t./team/b\n)\n")
            write_file(tmp .. "/team/go.work", "go 1.22\n\nuse ./b\n")
            touch(tmp .. "/team/a/go.mod")
            touch(tmp .. "/team/a/main.go")
            touch(tmp .. "/team/b/go.mod")
            touch(tmp .. "/team/b/main.go")
            assert.equals(abs(tmp .. "/team/a"), lsp_root.go_root(tmp .. "/team/a/main.go"))
            assert.equals(abs(tmp .. "/team"), lsp_root.go_root(tmp .. "/team/b/main.go"))
        end)

        it("resolves quoted use paths and dot segments", function()
            write_file(
                tmp .. "/go.work",
                'go 1.22\n\nuse (\n\t"./services/api"\n\t`./services/svc/../worker`\n)\n'
            )
            touch(tmp .. "/services/api/go.mod")
            touch(tmp .. "/services/api/main.go")
            touch(tmp .. "/services/worker/go.mod")
            touch(tmp .. "/services/worker/main.go")
            assert.equals(abs(tmp), lsp_root.go_root(tmp .. "/services/api/main.go"))
            assert.equals(abs(tmp), lsp_root.go_root(tmp .. "/services/worker/main.go"))
        end)

        it("roots a go.work buffer at that workspace", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse ./services/api\n")
            touch(tmp .. "/services/api/go.mod")
            assert.equals(abs(tmp), lsp_root.go_root(tmp .. "/go.work"))
        end)

        it("ignores go.work when GOWORK=off", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse ./mod\n")
            touch(tmp .. "/mod/go.mod")
            touch(tmp .. "/mod/main.go")
            assert.equals(abs(tmp .. "/mod"), lsp_root.go_root(tmp .. "/mod/main.go", { gowork = "off" }))
        end)

        it("uses the workspace file named by GOWORK when it lists the module", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse ./decoy\n")
            write_file(tmp .. "/workspaces/alt/go.work", "go 1.22\n\nuse ../../mod\n")
            touch(tmp .. "/mod/go.mod")
            touch(tmp .. "/mod/main.go")
            touch(tmp .. "/decoy/go.mod")
            local root = lsp_root.go_root(tmp .. "/mod/main.go", { gowork = tmp .. "/workspaces/alt/go.work" })
            assert.equals(abs(tmp .. "/workspaces/alt"), root)
        end)

        it("does not apply a GOWORK file that omits the module", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse ./mod\n")
            write_file(tmp .. "/workspaces/alt/go.work", "go 1.22\n\nuse ./somewhere\n")
            touch(tmp .. "/mod/go.mod")
            touch(tmp .. "/mod/main.go")
            local root = lsp_root.go_root(tmp .. "/mod/main.go", { gowork = tmp .. "/workspaces/alt/go.work" })
            assert.equals(abs(tmp .. "/mod"), root)
        end)

        it("uses the nearest go.mod when there is no go.work", function()
            mkdir(tmp .. "/.git")
            touch(tmp .. "/services/api/go.mod")
            touch(tmp .. "/services/api/main.go")
            local root = lsp_root.go_root(tmp .. "/services/api/main.go")
            assert.equals(abs(tmp .. "/services/api"), root)
        end)

        it("falls back to the git root", function()
            mkdir(tmp .. "/.git")
            touch(tmp .. "/main.go")
            local root = lsp_root.go_root(tmp .. "/main.go")
            assert.equals(abs(tmp), root)
        end)

        it("reuses the workspace root for module cache files", function()
            local cache = tmp .. "/pkg/mod"
            touch(cache .. "/github.com/acme/lib@v1.2.3/go.mod")
            touch(cache .. "/github.com/acme/lib@v1.2.3/lib.go")
            local root = lsp_root.go_root(cache .. "/github.com/acme/lib@v1.2.3/lib.go", {
                mod_cache = cache,
                reused_root = "/work/repo",
            })
            assert.equals("/work/repo", root)
        end)

        it("reuses the workspace root for stdlib files", function()
            local std = tmp .. "/goroot/src"
            touch(std .. "/fmt/print.go")
            local root = lsp_root.go_root(std .. "/fmt/print.go", {
                std_lib = std,
                reused_root = "/work/repo",
            })
            assert.equals("/work/repo", root)
        end)

        it("does not reuse a root for a project outside the cache", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse ./mod\n")
            touch(tmp .. "/mod/go.mod")
            touch(tmp .. "/mod/main.go")
            local root = lsp_root.go_root(tmp .. "/mod/main.go", {
                mod_cache = tmp .. "/pkg/mod",
                reused_root = "/somewhere/else",
            })
            assert.equals(abs(tmp), root)
        end)

        it("resolves the root after go env returns", function()
            write_file(tmp .. "/go.work", "go 1.22\n\nuse ./mod\n")
            touch(tmp .. "/mod/go.mod")
            touch(tmp .. "/mod/main.go")
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_name(buf, tmp .. "/mod/main.go")
            local root
            lsp_root.go_root_dir("gopls")(buf, function(dir)
                root = dir
            end)
            vim.wait(5000, function()
                return root ~= nil
            end)
            assert.equals(vim.uv.fs_realpath(tmp), vim.uv.fs_realpath(root))
            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)

    describe("typescript", function()
        it("uses the workspace lockfile above nested packages", function()
            touch(tmp .. "/pnpm-lock.yaml")
            touch(tmp .. "/packages/web/package.json")
            touch(tmp .. "/packages/web/tsconfig.json")
            touch(tmp .. "/packages/web/src/index.ts")
            touch(tmp .. "/packages/lib/package.json")
            touch(tmp .. "/packages/lib/tsconfig.json")
            local root, activate = lsp_root.typescript_root(tmp .. "/packages/web/src/index.ts")
            assert.is_true(activate)
            assert.equals(abs(tmp), root)
        end)

        it("treats npm yarn pnpm and bun lockfiles as the same priority", function()
            touch(tmp .. "/apps/web/package-lock.json")
            touch(tmp .. "/apps/web/src/index.ts")
            touch(tmp .. "/yarn.lock")
            local root = lsp_root.typescript_root(tmp .. "/apps/web/src/index.ts")
            assert.equals(abs(tmp .. "/apps/web"), root)
        end)

        it("falls back to the git root when there is no lockfile", function()
            mkdir(tmp .. "/.git")
            touch(tmp .. "/src/index.ts")
            local root, activate = lsp_root.typescript_root(tmp .. "/src/index.ts")
            assert.is_true(activate)
            assert.equals(abs(tmp), root)
        end)

        it("skips a deno package inside a node workspace", function()
            touch(tmp .. "/pnpm-lock.yaml")
            touch(tmp .. "/packages/deno/deno.json")
            touch(tmp .. "/packages/deno/main.ts")
            local root, activate = lsp_root.typescript_root(tmp .. "/packages/deno/main.ts")
            assert.is_nil(root)
            assert.is_false(activate)
        end)

        it("keeps a node package that is closer than deno", function()
            touch(tmp .. "/deno.json")
            touch(tmp .. "/packages/web/package-lock.json")
            touch(tmp .. "/packages/web/src/index.ts")
            local root, activate = lsp_root.typescript_root(tmp .. "/packages/web/src/index.ts")
            assert.is_true(activate)
            assert.equals(abs(tmp .. "/packages/web"), root)
        end)

        it("skips when a deno lock is closer than the node lock", function()
            touch(tmp .. "/package-lock.json")
            touch(tmp .. "/packages/deno/deno.lock")
            touch(tmp .. "/packages/deno/main.ts")
            local root, activate = lsp_root.typescript_root(tmp .. "/packages/deno/main.ts")
            assert.is_nil(root)
            assert.is_false(activate)
        end)

        it("activates with no root outside a project", function()
            touch(tmp .. "/notes.ts")
            local root, activate = lsp_root.typescript_root(tmp .. "/notes.ts")
            assert.is_nil(root)
            assert.is_true(activate)
        end)
    end)
end)
