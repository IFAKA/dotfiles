return {
  cmd = { "vscode-eslint-language-server", "--stdio" },
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte", "astro" },
  root_markers = { "eslint.config.js", "eslint.config.mjs", "eslint.config.cjs", ".eslintrc", ".git" },
  workspace_required = true,
  init_options = { documentFormatting = false },
}
