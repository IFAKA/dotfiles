-- LSP configuration and activation.
-- Server definitions live in local lsp/*.lua files; Neovim owns the client.

local typescript_language_server = vim.fn.exepath("typescript-language-server")
local node_command = vim.fn.exepath("node")
local npm_command = "npm"
if vim.fn.executable("brew") == 1 then
  local brew_bin = vim.fn.system({ "brew", "--prefix" }):gsub("%s+$", "") .. "/bin"
  local brew_tsls = brew_bin .. "/typescript-language-server"
  if vim.fn.executable(brew_tsls) == 1 then
    typescript_language_server = brew_tsls
    node_command = brew_bin .. "/node"
    npm_command = brew_bin .. "/npm"
  end
end

local global_typescript
local global_tsserver
local npm_roots = {}
if typescript_language_server ~= "" then
  local tsls_prefix = vim.fn.fnamemodify(
    vim.fn.fnamemodify(typescript_language_server, ":h"),
    ":h"
  )
  table.insert(npm_roots, tsls_prefix .. "/lib/node_modules")
end
if vim.fn.executable(npm_command) == 1 then
  local npm_root = vim.fn.system({ npm_command, "root", "-g" }):gsub("%s+$", "")
  table.insert(npm_roots, npm_root)
end

for _, npm_root in ipairs(npm_roots) do
  local candidate = npm_root .. "/typescript/lib"
  local tsserver = candidate .. "/tsserver.js"
  if vim.fn.isdirectory(candidate) == 1 and vim.fn.filereadable(tsserver) == 1 then
    global_typescript = candidate
    global_tsserver = tsserver
    break
  end
end

vim.lsp.config("ts_ls", {
  -- Prefer workspace TypeScript; use the global installation as fallback.
  cmd = typescript_language_server ~= "" and { node_command, typescript_language_server, "--stdio" } or nil,
  init_options = {
    preferences = { includePackageJsonAutoImports = "auto" },
    tsserver = global_tsserver and {
      path = global_tsserver,
      fallbackPath = global_typescript,
    } or nil,
  },
})

vim.lsp.config("eslint", {
  init_options = {
    documentFormatting = false,
  },
})

vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      diagnostics = { globals = { "vim" } },
      workspace = {
        library = vim.api.nvim_get_runtime_file("", true),
        checkThirdParty = false,
      },
      telemetry = { enable = false },
    },
  },
})

vim.lsp.config("tailwindcss", {
  settings = {
    tailwindCSS = {
      experimental = {
        classRegex = {
          { "class:\\s*\"([^\"]*)\"" },
          { "className:\\s*\"([^\"]*)\"" },
          { "className={\"([^\"}]*)\"}" },
        },
      },
    },
  },
})

vim.lsp.enable({
  "ts_ls",
  "html",
  "cssls",
  "jsonls",
  "tailwindcss",
  "eslint",
  "lua_ls",
  "pyright",
  "gopls",
  "clangd",
  "rust_analyzer",
})
