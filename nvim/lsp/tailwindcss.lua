return {
  cmd = { "tailwindcss-language-server", "--stdio" },
  filetypes = {
    "html", "css", "scss", "less", "sass", "javascript", "javascriptreact",
    "typescript", "typescriptreact", "vue", "svelte", "astro", "mdx",
  },
  root_markers = {
    "tailwind.config.js", "tailwind.config.cjs", "tailwind.config.mjs",
    "tailwind.config.ts", "postcss.config.js", "postcss.config.cjs", ".git",
  },
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
  workspace_required = true,
}
