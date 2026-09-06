-- Project discovery shared by the dashboard and project-aware commands.
local M = {}

M.markers = {
  ".git", "package.json", "Makefile", "dw.json", "tsconfig.json",
  "jsconfig.json", "tsconfig.base.json",
}

local function directory(path)
  path = vim.fs.normalize(vim.fn.resolve(path))
  return vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
end

function M.root(path)
  path = directory(path or vim.fn.getcwd())
  local marker = vim.fs.root(path, M.markers)
  return marker and vim.fs.normalize(vim.fn.resolve(marker)) or nil
end

function M.root_or_cwd(path)
  return M.root(path) or vim.fs.normalize(vim.fn.getcwd())
end

function M.recent()
  local projects, seen = {}, {}
  local function add(path)
    local root = M.root(path)
    if root and vim.fn.isdirectory(root) == 1 and not seen[root] then
      seen[root] = true
      table.insert(projects, root)
    end
  end

  add(vim.fn.getcwd())
  for _, file in ipairs(vim.v.oldfiles or {}) do
    if type(file) == "string" and vim.fn.filereadable(file) == 1 then add(file) end
  end
  return projects
end

return M
