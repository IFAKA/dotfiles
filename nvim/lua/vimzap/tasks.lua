-- Native project task runner. It discovers package.json scripts and runs them
-- through vim.system, using quickfix for compiler-style failures.
local M = {}
local projects = require("vimzap.projects")

local last_task
local task_bufnr

local function root_from(path)
  return projects.root_or_cwd(path)
end

function M.project_root(path)
  return root_from(path)
end

function M.discover(root)
  root = root or root_from()
  local tasks = {}
  local package_file = root .. "/package.json"

  if vim.fn.filereadable(package_file) == 1 then
    local ok, package = pcall(vim.json.decode, table.concat(vim.fn.readfile(package_file), "\n"))
    if ok and type(package) == "table" and type(package.scripts) == "table" then
      for name, script in pairs(package.scripts) do
        if type(name) == "string" and type(script) == "string" then
          table.insert(tasks, { name = name, description = script, kind = "npm" })
        end
      end
    end
  end

  if #tasks == 0 and vim.fn.filereadable(root .. "/Makefile") == 1 then
    table.insert(tasks, { name = "make", description = "make", kind = "make" })
  end

  table.sort(tasks, function(a, b) return a.name < b.name end)
  return tasks
end

function M.command_for(task)
  if task.kind == "make" or task.name == "make" then return { "make" } end
  return { "npm", "run", task.name }
end

function M.parse_error(line, root)
  local filename, lnum, col, message = line:match("^(.+):(%d+):(%d+):%s*(.*)$")
  if not filename then filename, lnum, message = line:match("^(.+):(%d+):%s*(.*)$") end
  if not filename then return nil end

  if filename:sub(1, 1) ~= "/" then filename = root .. "/" .. filename end
  return {
    filename = vim.fs.normalize(filename),
    lnum = tonumber(lnum),
    col = tonumber(col) or 1,
    text = message,
  }
end

local function output_buffer(name, lines)
  if task_bufnr and vim.api.nvim_buf_is_valid(task_bufnr) then
    vim.api.nvim_buf_set_lines(task_bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_name(task_bufnr, "VimZap task: " .. name)
    return
  end

  task_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(task_bufnr, "VimZap task: " .. name)
  vim.api.nvim_buf_set_lines(task_bufnr, 0, -1, false, lines)
  vim.bo[task_bufnr].buftype = "nofile"
  vim.bo[task_bufnr].bufhidden = "hide"
  vim.bo[task_bufnr].swapfile = false
  vim.bo[task_bufnr].filetype = "vimzap-task"
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, task_bufnr)
end

function M.run(task, root)
  root = root or root_from()
  last_task = { task = task, root = root }
  local command = M.command_for(task)
  output_buffer(task.name, { "$ " .. table.concat(command, " "), "" })

  vim.system(command, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      local output = (result.stdout or "") .. (result.stderr or "")
      local lines = vim.split(output, "\n", { trimempty = true })
      if #lines == 0 then lines = { "(no output)" } end
      output_buffer(task.name, vim.list_extend({ "$ " .. table.concat(command, " "), "" }, lines))

      local items = {}
      for _, line in ipairs(lines) do
        local item = M.parse_error(line, root)
        if item then table.insert(items, item) end
      end
      vim.fn.setqflist({}, " ", { title = "VimZap: " .. task.name, items = items })

      if result.code == 0 then
        vim.notify("Task completed: " .. task.name)
      else
        vim.notify(string.format("Task failed (%d): %s", result.code, task.name), vim.log.levels.ERROR)
        if #items > 0 then vim.cmd("copen") end
      end
    end)
  end)
end

function M.pick()
  local root = root_from()
  local tasks = M.discover(root)
  if #tasks == 0 then
    vim.notify("No package.json scripts or Makefile found", vim.log.levels.WARN)
    return
  end
  vim.ui.select(tasks, {
    prompt = "Run project task",
    format_item = function(task) return string.format("%-16s %s", task.name, task.description) end,
  }, function(task)
    if task then M.run(task, root) end
  end)
end

function M.rerun()
  if not last_task then
    vim.notify("No VimZap task has run yet", vim.log.levels.WARN)
    return
  end
  M.run(last_task.task, last_task.root)
end

function M.open_quickfix()
  if #vim.fn.getqflist() == 0 then
    vim.notify("Task quickfix is empty")
    return
  end
  vim.cmd("copen")
end

return M
