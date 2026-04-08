local opts = {
  adapters = {
    ["neotest-go"] = {
      args = { "-coverprofile=coverage.out" },
    },
    ["neotest-python"] = {
      args = {"--log-level", "DEBUG"},
      runner = "env/bin/pytest",
      python = "env/bin/python",
    },
    ["neotest-jest"] = {
      cwd = function()
        return vim.fn.getcwd()
      end,
    },
    ["neotest-vitest"] = {},
    ["neotest-java"] = {
      filetypes = { "java", "kotlin" },
      junit_jar = "~/.config/tools/unit-platform-console-standalone-1.10.2.jar",
    },
  },
}

local neotest_ns = vim.api.nvim_create_namespace("neotest")
vim.diagnostic.config({
  virtual_text = {
    format = function(diagnostic)
      local message =
        diagnostic.message:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+", "")
      return message
    end,
  },
}, neotest_ns)

if opts.adapters then
  local adapters = {}
  for name, config in pairs(opts.adapters or {}) do
    if type(name) == "number" then
      if type(config) == "string" then
        config = require(config)
      end
      adapters[#adapters + 1] = config
    elseif config ~= false then
      local adapter = require(name)
      if type(config) == "table" and not vim.tbl_isempty(config) then
        local meta = getmetatable(adapter)
        if adapter.setup then
          adapter.setup(config)
        elseif adapter.adapter then
          adapter.adapter(config)
          adapter = adapter.adapter
        elseif meta and meta.__call then
          adapter(config)
        else
          error("Adapter " .. name .. " does not support setup")
        end
      end
      adapters[#adapters + 1] = adapter
    end
  end
  opts.adapters = adapters
end

require("neotest").setup(opts)

require("coverage").setup({
  auto_reload = true,
  lang = {
    javascript = {
      coverage_file = ".coverage/lcov.info",
    },
    go = {
      coverage_file = "coverage.out",
    },
  },
})

