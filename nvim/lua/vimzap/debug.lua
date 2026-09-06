-- Debug (nvim-dap), initialized on first debugger action.
local M = {}
local initialized = false

function M.setup()
  if initialized then return end
  initialized = true

  local dap = require("dap")
  local dapui = require("dapui")

  local function notify_warn(message)
    vim.schedule(function()
      vim.notify(message, vim.log.levels.WARN, { title = "nvim-dap" })
    end)
  end

  dapui.setup({
    layouts = {
      {
        elements = {
          { id = "scopes", size = 0.5 },
          { id = "breakpoints", size = 0.25 },
          { id = "stacks", size = 0.25 },
        },
        size = 40,
        position = "left",
      },
      {
        elements = { "repl", "console" },
        size = 0.25,
        position = "bottom",
      },
    },
  })

  dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
  dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
  dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end

  vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
  vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticOk", linehl = "CursorLine" })

  local js_debug_adapter = vim.fn.exepath("js-debug-adapter")
  if js_debug_adapter ~= "" then
    dap.adapters["pwa-node"] = {
      type = "server",
      host = "localhost",
      port = "${port}",
      executable = { command = js_debug_adapter, args = { "${port}" } },
    }
  else
    notify_warn("js-debug-adapter not found on PATH; Node.js debugging is disabled")
  end

  local function find_prophet_adapter()
    local extension_root = vim.fn.expand("~/.vscode/extensions")
    local extensions = vim.fn.globpath(extension_root, "sqrtt.prophet-*", false, true)
    table.sort(extensions)

    for i = #extensions, 1, -1 do
      local adapter_path = extensions[i] .. "/dist/mockDebug.js"
      if vim.fn.filereadable(adapter_path) == 1 then return adapter_path end
    end
  end

  local js_config = {
    {
      type = "pwa-node", request = "attach", name = "Attach to Node (port 9229)",
      port = 9229, cwd = "${workspaceFolder}", sourceMaps = true,
      resolveSourceMapLocations = { "${workspaceFolder}/**", "!**/node_modules/**" },
      skipFiles = { "<node_internals>/**", "**/node_modules/**" },
    },
    {
      type = "pwa-node", request = "launch", name = "Launch current file",
      program = "${file}", cwd = "${workspaceFolder}", sourceMaps = true,
    },
    {
      type = "pwa-node", request = "launch", name = "Launch Node (ask for file)",
      program = function() return vim.fn.input("Path to file: ", vim.fn.getcwd() .. "/", "file") end,
      cwd = "${workspaceFolder}", sourceMaps = true,
    },
  }

  local prophet_adapter = find_prophet_adapter()
  local javascript_config = js_config
  if prophet_adapter then
    dap.adapters.prophet = { type = "executable", command = "node", args = { prophet_adapter } }
    local sfcc_config = {
      type = "prophet", request = "attach", name = "Attach to SFCC Sandbox",
      cwd = "${workspaceFolder}", trace = true,
    }
    javascript_config = { sfcc_config }
    vim.list_extend(javascript_config, js_config)
    dap.configurations.dwscript = { sfcc_config }
  else
    notify_warn("Prophet VS Code extension not found at ~/.vscode/extensions/sqrtt.prophet-*; SFCC debugging disabled")
  end

  dap.configurations.javascript = javascript_config
  dap.configurations.typescript = js_config
  dap.configurations.javascriptreact = js_config
  dap.configurations.typescriptreact = js_config
end

return M
