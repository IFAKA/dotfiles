vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.undofile = true
vim.opt.updatetime = 250
vim.opt.clipboard = "unnamedplus"
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.wrap = false
vim.opt.linebreak = true
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.autocomplete = true
vim.opt.completeopt = "menuone,noselect,popup,fuzzy"
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false
vim.filetype.add({ extension = { ds = "ds", isml = "isml" } })
vim.diagnostic.config({ virtual_text = true, float = { border = "rounded" } })
