-- Native startup dashboard using VimZap's existing commands and pickers.
local projects = require("vimzap.projects")
local M = {}

local function open_dashboard()
  if vim.fn.argc() ~= 0 or vim.api.nvim_buf_get_name(0) ~= "" or vim.bo.buftype ~= "" then return end

  local recent = projects.recent()
  local buf = vim.api.nvim_create_buf(false, true)
  local git_line = 1
  local function render(status)
    local lines = { "", "  VimZap", "", "  Recent Projects", "" }
    if #recent == 0 then
      table.insert(lines, "  No recent projects found.")
    else
      for index, root in ipairs(recent) do
        table.insert(lines, string.format("  %d  %s", index, root))
      end
    end
    table.insert(lines, "")
    git_line = #lines + 1
    table.insert(lines, "  Git Status  " .. (status or "Loading..."))
    table.insert(lines, "")
    table.insert(lines, "  Actions")
    table.insert(lines, "  f  Find files       g  Grep project")
    table.insert(lines, "  r  Recent files     b  Buffers")
    table.insert(lines, "  t  Project tasks    s  Git status")
    table.insert(lines, "  T  Terminal         ?  Help")
    table.insert(lines, "")
    table.insert(lines, "  Press a number to open a project, or q to quit.")
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  render()
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "vimzap-dashboard"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.cursorline = false

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end
  local function select_project(index)
    local root = recent[index]
    if not root then return end
    vim.api.nvim_set_current_dir(root)
    M.refresh_git(buf, git_line)
    vim.cmd("VimZapFiles")
  end
  for index = 1, #recent do map(tostring(index), function() select_project(index) end, "Open project") end
  map("f", "<cmd>VimZapFiles<cr>", "Find files")
  map("g", "<cmd>VimZapGrep<cr>", "Grep project")
  map("r", "<cmd>VimZapRecent<cr>", "Recent files")
  map("b", "<cmd>VimZapBuffers<cr>", "Buffers")
  map("t", "<cmd>VimZapTasks<cr>", "Project tasks")
  map("s", "<leader>gs", "Git status")
  map("T", "<cmd>VimZapTerminalToggle<cr>", "Terminal")
  map("?", function() MiniPick.builtin.help({}) end, "Help")
  map("q", "<cmd>quit<cr>", "Quit")

  M.refresh_git(buf, git_line)
end

function M.refresh_git(buf, line)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local root = projects.root(vim.fn.getcwd())
  local function update(text)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local current = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
      if current and current:match("^  Git Status") then
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, line - 1, line, false, { "  Git Status  " .. text })
        vim.bo[buf].modifiable = false
      end
    end)
  end
  if not root then update("not a Git project"); return end
  vim.system({ "git", "status", "--porcelain=v1", "--branch" }, { cwd = root, text = true }, function(result)
    if result.code ~= 0 then update("not a Git project"); return end
    local branch, staged, modified, deleted, untracked = "(detached)", 0, 0, 0, 0
    for status in (result.stdout or ""):gmatch("[^\n]+") do
      if status:sub(1, 2) == "##" then
        branch = status:sub(4):gsub("%.%.%..*$", "")
      elseif status:sub(1, 2) == "??" then
        untracked = untracked + 1
      else
        local index, worktree = status:sub(1, 1), status:sub(2, 2)
        if index ~= " " then staged = staged + 1 end
        if worktree ~= " " then modified = modified + 1 end
        if index == "D" or worktree == "D" then deleted = deleted + 1 end
      end
    end
    local counts = string.format("staged %d · modified %d · deleted %d · untracked %d", staged, modified, deleted, untracked)
    update(branch .. " · " .. counts)
  end)
end

vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = open_dashboard })

return M
