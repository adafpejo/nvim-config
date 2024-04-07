local project_root = {
    function()
        return vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
    end,
    icon = "",
    color = { bg = "#eaab23", fg = "black" },
    separator = '',
}

return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
        local lualine = require("lualine")
        local lazy_status = require("lazy.status") -- to configure lazy pending updates count

        local colors = {
            blue = "#65D1FF",
            green = "#3EFFDC",
            violet = "#FF61EF",
            yellow = "#FFDA7B",
            red = "#FF4A4A",
            fg = "#c3ccdc",
            bg = "#112638",
            inactive_bg = "#2c3043",
        }

        local custom_fname = require('lualine.components.filename'):extend()
        local highlight = require 'lualine.highlight'
        local default_status_colors = { saved = '#228B22', modified = '#C70039' }

        function custom_fname:init(options)
            custom_fname.super.init(self, options)
            self.status_colors = {
                saved = highlight.create_component_highlight_group(
                    { bg = default_status_colors.saved }, 'filename_status_saved', self.options),
                modified = highlight.create_component_highlight_group(
                    { bg = default_status_colors.modified }, 'filename_status_modified', self.options),
            }
            if self.options.color == nil then self.options.color = '' end
        end

        function custom_fname:update_status()
            local data = custom_fname.super.update_status(self)
            data = highlight.component_format_highlight(vim.bo.modified
                and self.status_colors.modified
                or self.status_colors.saved) .. data
            return data
        end

        local my_lualine_theme = {
            normal = {
                a = { bg = colors.blue, fg = colors.bg, gui = "bold" },
                b = { bg = colors.bg, fg = colors.fg },
                c = { bg = colors.bg, fg = colors.fg },
            },
            insert = {
                a = { bg = colors.green, fg = colors.bg, gui = "bold" },
                b = { bg = colors.bg, fg = colors.fg },
                c = { bg = colors.bg, fg = colors.fg },
            },
            visual = {
                a = { bg = colors.violet, fg = colors.bg, gui = "bold" },
                b = { bg = colors.bg, fg = colors.fg },
                c = { bg = colors.bg, fg = colors.fg },
            },
            command = {
                a = { bg = colors.yellow, fg = colors.bg, gui = "bold" },
                b = { bg = colors.bg, fg = colors.fg },
                c = { bg = colors.bg, fg = colors.fg },
            },
            replace = {
                a = { bg = colors.red, fg = colors.bg, gui = "bold" },
                b = { bg = colors.bg, fg = colors.fg },
                c = { bg = colors.bg, fg = colors.fg },
            },
            inactive = {
                a = { bg = colors.inactive_bg, fg = colors.semilightgray, gui = "bold" },
                b = { bg = colors.inactive_bg, fg = colors.semilightgray },
                c = { bg = colors.inactive_bg, fg = colors.semilightgray },
            },
        }

        -- configure lualine with modified theme
        lualine.setup({
            options = {
                theme = my_lualine_theme,
            },
            sections = {
                lualine_b = {
                    project_root, -- Make sure project_root is a function or variable that returns a string
                    { "branch" },
                },
                lualine_c = { { custom_fname, color = { fg = "black" }, file_status = true, newfile_status = true, path = 1 } }
            },
        })
    end,
}
