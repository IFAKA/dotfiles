-- Keep only plugins for protocols and domain features Neovim does not provide.
local projects = require("vimzap.projects")
local plugins = {
  "https://github.com/echasnovski/mini.nvim",
  "https://github.com/folke/flash.nvim",
  "https://github.com/folke/which-key.nvim",
  "https://github.com/mfussenegger/nvim-dap",
  "https://github.com/nvim-neotest/nvim-nio",
  "https://github.com/rcarriga/nvim-dap-ui",
}
local sfcc = projects.is_sfcc()
if sfcc then
  table.insert(plugins, { src = "https://github.com/IFAKA/prophet.nvim", version = "v2.*" })
end
vim.pack.add(plugins, { confirm = false, load = true })

require("mini.pick").setup()
require("flash").setup()
require("which-key").setup({ delay = 300 })

if sfcc then
  require("prophet").setup({
    auto_upload = false, clean_on_start = false, notify = true, dap = { enabled = true },
  })
end
