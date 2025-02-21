-- don't use packages here, use only after lazy_init
--
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- cursor change on insert mode
vim.opt.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20"

vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- vim.opt.smartindent = true

-- vim.opt.wrap = false
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.list = false
vim.opt.textwidth = 120
vim.opt.wrapmargin = 0


vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.updatetime = 50

vim.opt.colorcolumn = "80"

-- The unnamedplus option makes nvim use the system clipboard for all yank, delete, and put operations that would normally go to the unnamed register.
vim.opt.clipboard = "unnamedplus"
