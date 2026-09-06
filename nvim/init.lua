-- VimZap: a minimal Neovim configuration for coding and SFCC development.
require("options")
require("plugins")
require("lsp")
require("keymaps")
require("vimzap.dashboard")

-- Load custom user configuration (optional)
-- Create ~/.config/nvim/vimzap-custom.lua to override settings
local custom_config = vim.fn.stdpath("config") .. "/vimzap-custom.lua"
if vim.fn.filereadable(custom_config) == 1 then
  dofile(custom_config)
end
