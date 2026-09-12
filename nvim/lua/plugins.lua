-- Keep only plugins for protocols and domain features Neovim does not provide.
vim.pack.add({
  "https://github.com/folke/which-key.nvim",
  "https://github.com/mfussenegger/nvim-dap",
  "https://github.com/nvim-neotest/nvim-nio",
  "https://github.com/rcarriga/nvim-dap-ui",
  { src = "https://github.com/IFAKA/prophet.nvim", version = "v2.*" },
}, { confirm = false, load = true })

require("which-key").setup({ delay = 300 })

require("prophet").setup({
  auto_upload = false, clean_on_start = false, notify = true, dap = { enabled = true },
})
