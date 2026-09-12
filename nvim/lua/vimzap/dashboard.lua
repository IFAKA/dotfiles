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
  local function render()
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

end

vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = open_dashboard })

return M
