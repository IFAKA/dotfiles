-- Keep only plugins for features Neovim does not provide itself.
vim.pack.add({
  "https://github.com/echasnovski/mini.nvim",
  "https://github.com/folke/which-key.nvim",
  "https://github.com/lewis6991/gitsigns.nvim",
  "https://github.com/neovim/nvim-lspconfig",
  "https://github.com/mfussenegger/nvim-dap",
  "https://github.com/nvim-neotest/nvim-nio",
  "https://github.com/rcarriga/nvim-dap-ui",
  { src = "https://github.com/IFAKA/prophet.nvim", version = "v2.*" },
}, { confirm = false, load = true })

require("mini.pick").setup()
require("which-key").setup({ delay = 300 })
require("gitsigns").setup({
  signs = { add = { text = "+" }, change = { text = "~" }, delete = { text = "_" }, topdelete = { text = "‾" }, changedelete = { text = "~" } },
  current_line_blame = true,
  current_line_blame_opts = { virt_text = true, virt_text_pos = "eol", delay = 500 },
})

local prophet_ok, prophet = pcall(require, "prophet")
if prophet_ok then
  prophet.setup({
    auto_upload = false, clean_on_start = false, notify = true, dap = { enabled = true },
  })
else
  vim.notify("Prophet plugin will be available after the next Neovim start", vim.log.levels.WARN)
end
