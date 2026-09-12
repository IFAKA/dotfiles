-- Native startup dashboard using VimZap's existing commands and pickers.
local projects = require("vimzap.projects")
local M = {}

local function open_dashboard()
  if vim.fn.argc() ~= 0 or vim.api.nvim_buf_get_name(0) ~= "" or vim.bo.buftype ~= "" then return end

  local recent = projects.recent()
  local recent_files = vim.tbl_filter(function(path)
    return type(path) == "string" and vim.fn.filereadable(path) == 1
  end, vim.v.oldfiles or {})
  local recent_file_lines = {}
  local recent_file_limit = 8
  local buf = vim.api.nvim_create_buf(false, true)
  local git_line = 1
  local function render(status)
    local lines = { "", "  VimZap", "", "  Recent Files", "" }
    recent_file_lines = {}
    if #recent_files == 0 then
      table.insert(lines, "  No recent files found.")
    else
      for index, path in ipairs(recent_files) do
        if index > recent_file_limit then break end
        table.insert(lines, "  " .. vim.fn.fnamemodify(path, ":~:."))
        recent_file_lines[#lines] = path
      end
    end
    table.insert(lines, "")
    git_line = #lines + 1
    table.insert(lines, "  Git Status  " .. (status or "Loading..."))
    table.insert(lines, "")
    table.insert(lines, "  Actions")
    table.insert(lines, "  f  Find files       r  Recent files")
    table.insert(lines, "  g  Grep project     p  Projects")
    table.insert(lines, "  q  Quit")
    table.insert(lines, "")
    table.insert(lines, "  Other commands are available through the leader menu.")
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
  vim.wo.cursorline = true
  if next(recent_file_lines) then
    vim.api.nvim_win_set_cursor(0, { next(recent_file_lines), 0 })
  end

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end
  map("p", function()
    MiniPick.start({
      source = {
        items = recent,
        name = "Projects",
        choose = function(root)
          vim.api.nvim_set_current_dir(root)
          M.refresh_git(buf, git_line)
          vim.cmd("VimZapFiles")
        end,
      },
    })
  end, "Projects")
  map("r", function()
    vim.cmd("VimZapRecent")
  end, "Recent files")
  map("<CR>", function()
    local path = recent_file_lines[vim.api.nvim_win_get_cursor(0)[1]]
    if not path then return end
    local root = projects.root(path)
    if root then vim.api.nvim_set_current_dir(root) end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end, "Open recent file")
  map("f", "<cmd>VimZapFiles<cr>", "Find files")
  map("g", "<cmd>VimZapGrep<cr>", "Grep project")
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
