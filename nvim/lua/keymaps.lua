local function map(lhs, rhs, desc, mode)
  vim.keymap.set(mode or "n", lhs, rhs, { desc = desc })
end

map("jj", "<Esc>", "Exit insert mode", "i")
local tasks = require("vimzap.tasks")
local projects = require("vimzap.projects")

local function project_root()
  return projects.root_or_cwd()
end

local function files()
  MiniPick.builtin.files({ tool = "git" })
end

local function grep()
  MiniPick.builtin.grep_live()
end

local function buffers() MiniPick.builtin.buffers() end
local function recent_files()
  MiniPick.start({ source = { items = vim.v.oldfiles, name = "Recent files" } })
end
local git_command

local function select_commands()
  local commands = vim.api.nvim_get_commands({ builtin = false })
  local items = {}
  for name, command in pairs(commands) do
    table.insert(items, { name = name, description = command.definition or "" })
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  vim.ui.select(items, {
    prompt = "Commands",
    format_item = function(item) return item.name .. "  " .. item.description end,
  }, function(item)
    if item then vim.cmd(item.name) end
  end)
end

local function select_diagnostics()
  local items = vim.diagnostic.toqflist(vim.diagnostic.get())
  if #items == 0 then
    vim.notify("No diagnostics")
    return
  end
  vim.ui.select(items, {
    prompt = "Diagnostics",
    format_item = function(item)
      return string.format("%s:%d:%d  %s", item.filename, item.lnum, item.col, item.text)
    end,
  }, function(item)
    if not item then return end
    local bufnr = vim.fn.bufadd(item.filename)
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { item.lnum, math.max(item.col - 1, 0) })
  end)
end

local function select_commits()
  local lines = vim.fn.systemlist({ "git", "log", "--oneline", "--decorate", "-100" })
  if vim.v.shell_error ~= 0 or #lines == 0 then
    vim.notify("No Git commits found", vim.log.levels.WARN)
    return
  end
  vim.ui.select(lines, { prompt = "Git commits" }, function(line)
    if not line then return end
    local sha = line:match("^(%S+)")
    if sha then git_command("show " .. sha) end
  end)
end

git_command = function(command)
  vim.cmd("botright split | terminal git " .. command)
  vim.cmd("startinsert")
end

local function copy_project_path()
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then return end
  filepath = vim.fs.normalize(vim.fn.resolve(filepath))
  local root = vim.fs.normalize(vim.fn.resolve(project_root()))
  local prefix = root .. "/"
  local relative = filepath:sub(1, #prefix) == prefix and filepath:sub(#prefix + 1) or filepath
  vim.fn.setreg("+", relative)
  vim.notify("Copied: " .. relative)
end

local terminal_bufnr

local function toggle_terminal()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if vim.bo[bufnr].buftype == "terminal" then
      terminal_bufnr = bufnr
      vim.api.nvim_win_hide(win)
      return
    end
  end

  if not terminal_bufnr or not vim.api.nvim_buf_is_valid(terminal_bufnr) then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal" then
        terminal_bufnr = bufnr
        break
      end
    end
  end

  vim.cmd("botright split")
  if terminal_bufnr and vim.api.nvim_buf_is_valid(terminal_bufnr) then
    vim.api.nvim_win_set_buf(0, terminal_bufnr)
  else
    vim.cmd("terminal")
    terminal_bufnr = vim.api.nvim_get_current_buf()
  end
  vim.cmd("startinsert")
end

vim.api.nvim_create_user_command("VimZapTerminalToggle", toggle_terminal, {})

local function lsp_cmd(fn)
  return function()
    if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then fn() end
  end
end

local function dap_action(method)
  return function()
    require("vimzap.debug").setup()
    require("dap")[method]()
  end
end

vim.api.nvim_create_user_command("VimZapFiles", files, {})
vim.api.nvim_create_user_command("VimZapGrep", grep, {})
vim.api.nvim_create_user_command("VimZapBuffers", buffers, {})
vim.api.nvim_create_user_command("VimZapRecent", recent_files, {})
vim.api.nvim_create_user_command("VimZapTasks", tasks.pick, {})
vim.api.nvim_create_user_command("VimZapTaskLast", tasks.rerun, {})
vim.api.nvim_create_user_command("VimZapTaskQuickfix", tasks.open_quickfix, {})
vim.api.nvim_create_user_command("VimZapTask", function(opts)
  local root = tasks.project_root()
  for _, task in ipairs(tasks.discover(root)) do
    if task.name == opts.args then
      tasks.run(task, root)
      return
    end
  end
  vim.notify("Unknown project task: " .. opts.args, vim.log.levels.ERROR)
end, {
  nargs = 1,
  complete = function()
    return vim.tbl_map(function(task) return task.name end, tasks.discover(tasks.project_root()))
  end,
})

map("<leader>w", "<cmd>w<cr>", "Save")
map("<leader>ff", files, "Find files")
map("<leader>fg", grep, "Grep project")
map("<leader>fb", buffers, "Find buffers")
map("<leader>fr", recent_files, "Recent files")
map("<leader>fp", copy_project_path, "Copy project path")
map("<leader>ca", lsp_cmd(vim.lsp.buf.code_action), "Code action")
map("<leader>cr", lsp_cmd(vim.lsp.buf.rename), "Rename symbol")
map("<leader>cf", lsp_cmd(function() vim.lsp.buf.format({ async = true }) end), "Format")
map("<leader>co", lsp_cmd(function()
  vim.lsp.buf.code_action({ apply = true, context = { only = { "source.removeUnusedImports.ts" }, diagnostics = {} } })
end), "Remove unused imports")
map("<leader>rr", tasks.pick, "Run project task")
map("<leader>rl", tasks.rerun, "Rerun last task")
map("<leader>rq", tasks.open_quickfix, "Open task quickfix")
map("<leader>cd", vim.diagnostic.open_float, "Line diagnostics")
map("<leader>cs", lsp_cmd(vim.lsp.buf.document_symbol), "Document symbols")
map("<leader>gf", function() git_command("ls-files") end, "Git files")
map("<leader>gs", function() git_command("status") end, "Git status")
map("<leader>gc", select_commits, "Find Git commits")
map("<leader>gp", "<cmd>Gitsigns preview_hunk<cr>", "Preview hunk")
map("<leader>ga", "<cmd>Gitsigns stage_hunk<cr>", "Stage hunk")
map("<leader>gr", "<cmd>Gitsigns reset_hunk<cr>", "Reset hunk")
map("<leader>gb", "<cmd>Gitsigns blame_line<cr>", "Blame line")
map("<leader>sh", function() MiniPick.builtin.help() end, "Find help")
map("<leader>sk", "<cmd>map<cr>", "Show keymaps")
map("<leader>sc", select_commands, "Find commands")
map("<leader>sd", select_diagnostics, "Find diagnostics")
map("<leader>?", function() MiniPick.builtin.help({}) end, "Find help")
map("<leader>db", dap_action("toggle_breakpoint"), "Debug breakpoint")
map("<leader>dB", function() require("vimzap.debug").setup(); require("dap").set_breakpoint(vim.fn.input("Condition: ")) end, "Debug conditional breakpoint")
map("<leader>dc", dap_action("continue"), "Debug continue/start")
map("<leader>di", dap_action("step_into"), "Debug step into")
map("<leader>do", dap_action("step_over"), "Debug step over")
map("<leader>dO", dap_action("step_out"), "Debug step out")
map("<leader>dr", dap_action("restart"), "Debug restart")
map("<leader>dq", dap_action("terminate"), "Debug stop")
map("<leader>du", function() require("vimzap.debug").setup(); require("dapui").toggle() end, "Debug UI")
map("<leader>de", function() require("vimzap.debug").setup(); require("dapui").eval() end, "Debug evaluate", { "n", "v" })
map("<leader>pc", "<cmd>ProphetClean<cr>", "Prophet upload all cartridges")
map("<leader>pt", "<cmd>ProphetToggle<cr>", "Prophet toggle auto-upload")
map("<leader>ps", "<cmd>ProphetStatus<cr>", "Prophet status")
map("<leader>pe", "<cmd>ProphetEnable<cr>", "Prophet enable auto-upload")
map("<leader>pd", "<cmd>ProphetDisable<cr>", "Prophet disable auto-upload")
map("<leader>pu", "<cmd>ProphetUpload<cr>", "Prophet upload cartridge")
map("<leader>pC", "<cmd>ProphetCheckSandbox<cr>", "Prophet check sandbox")
map("<leader>pf", "<cmd>ProphetControllers<cr>", "Find SFCC controller")
map("<leader>pi", "<cmd>ProphetTemplates<cr>", "Find ISML template")
map("<leader>pl", "<cmd>ProphetLogs<cr>", "View SFCC logs")
map("<leader>pr", "<cmd>ProphetRefresh<cr>", "Refresh SFCC controllers")
map("[d", function() vim.diagnostic.jump({ count = -1 }) end, "Previous diagnostic")
map("]d", function() vim.diagnostic.jump({ count = 1 }) end, "Next diagnostic")
map("[e", function() vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR }) end, "Previous error")
map("]e", function() vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR }) end, "Next error")
map("[q", "<cmd>cprevious<cr>", "Previous task error")
map("]q", "<cmd>cnext<cr>", "Next task error")
map("[h", "<cmd>Gitsigns nav_hunk prev<cr>", "Previous hunk")
map("]h", "<cmd>Gitsigns nav_hunk next<cr>", "Next hunk")
map("<S-h>", "<cmd>bprevious<cr>", "Previous buffer")
map("<S-l>", "<cmd>bnext<cr>", "Next buffer")
map("<leader>bd", "<cmd>bdelete<cr>", "Delete buffer")
map("<leader>bo", "<cmd>%bd|e#|bd#<cr>", "Close other buffers")
map("<C-/>", toggle_terminal, "Terminal", { "n", "t" })
map("<C-_>", toggle_terminal, "Terminal", { "n", "t" })
map("<C-Space>", function() vim.lsp.completion.get() end, "Trigger LSP completion", "i")

local which_key_ok, which_key = pcall(require, "which-key")
if which_key_ok then
  which_key.add({
    { "<leader>f", group = "Find / files" },
    { "<leader>c", group = "Code" },
    { "<leader>r", group = "Run / tasks" },
    { "<leader>d", group = "Debug" },
    { "<leader>g", group = "Git" },
    { "<leader>p", group = "Prophet / SFCC" },
    { "<leader>s", group = "Search / help" },
  })
end

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    if client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
    end
    local function lsp_map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = args.buf, desc = desc })
    end
    lsp_map("n", "gd", vim.lsp.buf.definition, "Go to definition")
    lsp_map("n", "gr", vim.lsp.buf.references, "Go to references")
    lsp_map("n", "gi", vim.lsp.buf.implementation, "Go to implementation")
    lsp_map("n", "gy", vim.lsp.buf.type_definition, "Go to type definition")
    lsp_map("n", "K", vim.lsp.buf.hover, "Hover documentation")
    lsp_map("i", "<C-k>", vim.lsp.buf.signature_help, "Signature help")
  end,
})
