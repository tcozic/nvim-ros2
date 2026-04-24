local M = {}
local Utils = require("nvim-ros2.utils")
local function get_command_output(cmd)
  if vim.fn.executable("ros2") ~= 1 then
    vim.notify("ros2 not found", vim.log.levels.ERROR)
    return nil
  end
  return vim.fn.systemlist(cmd)
end

local function ros_picker(opts)
  local output = get_command_output(opts.system_cmd)
  if not output then
    return
  end

  local fzf = require("fzf-lua")
  fzf.fzf_exec(output, {
    prompt = opts.prompt_title .. "> ",
    preview = function(selected)
      if not selected or #selected == 0 then
        return {}
      end
      local item = selected[1]
      local cmd = { "ros2", opts.command, opts.mode, item }
      if opts.args and opts.args ~= "" then
        table.insert(cmd, opts.args)
      end
      return vim.fn.systemlist(cmd)
    end,
    actions = {
      ["default"] = function(selected)
        -- Sprint 4: Trigger Tuner callback if provided
        if opts.on_select and selected and #selected > 0 then
          opts.on_select(selected[1])
        end
      end,
    },
  })
end
function M.interfaces()
  local command = { "ros2", "interface", "list" }
  local raw_output = get_command_output(command)
  if not raw_output then
    return
  end

  local items = {}
  for _, line in ipairs(raw_output) do
    local section_header = line:match("^%s*(%a+):$")
    if not section_header then
      local trimmed_line = line:match("^%s*(.-)%s*$")
      if trimmed_line ~= "" then
        table.insert(items, trimmed_line)
      end
    end
  end

  local fzf = require("fzf-lua")
  fzf.fzf_exec(items, {
    prompt = "Select Interface> ",
    preview = function(selected)
      if not selected or #selected == 0 then
        return {}
      end
      local item = selected[1]
      local cmd = { "ros2", "interface", "show", item }
      return vim.fn.systemlist(cmd)
    end,
    actions = {
      ["default"] = function() end,
    },
  })
end

function M.nodes(opts)
  opts = opts or {}
  local node_opts = vim.tbl_extend("force", {
    prompt_title = "Active Nodes",
    system_cmd = { "ros2", "node", "list" },
    command = "node",
    mode = "info",
    args = "--include-hidden",
  }, opts)

  ros_picker(node_opts)
end

function M.actions()
  ros_picker({
    prompt_title = "Active Actions",
    system_cmd = { "ros2", "action", "list" },
    command = "action",
    mode = "info",
    args = "--show-types",
  })
end

function M.services()
  ros_picker({
    prompt_title = "Active Services",
    system_cmd = { "ros2", "service", "list" },
    command = "service",
    mode = "type",
    args = "",
  })
end

function M.topics_info()
  ros_picker({
    prompt_title = "Active Topics",
    system_cmd = { "ros2", "topic", "list" },
    command = "topic",
    mode = "info",
    args = "--verbose",
  })
end

function M.topics_echo()
  ros_picker({
    prompt_title = "Active Topics",
    system_cmd = { "ros2", "topic", "list" },
    command = "topic",
    mode = "echo",
    args = "--once",
  })
end

function M.packages()
  local ws_root = Utils.get_workspace_root(0)

  require("fzf-lua").files({
    prompt = "ROS 2 Packages> ",
    cwd = ws_root,
    cmd = vim.fn.executable("fd") == 1 and "fd ^package.xml$ --exclude build --exclude install"
      or "find . -name package.xml -not -path '*/install/*' -not -path '*/build/*'",
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        -- fzf-lua returns the file path, we need its directory
        local pkg_dir = vim.fs.dirname(ws_root .. "/" .. selected[1])
        if pcall(require, "oil") then
          require("oil").open(pkg_dir)
        else
          vim.cmd("edit " .. pkg_dir)
        end
      end,
    },
  })
end

function M.sniper(subdir)
  local pkg = Utils.find_package_root()
  if not pkg then
    return
  end
  local target = pkg .. "/" .. subdir

  if vim.fn.isdirectory(target) == 0 then
    vim.fn.mkdir(target, "p")
  end

  local files = vim.split(vim.fn.glob(target .. "/*"), "\n", { trimempty = true })
  if #files == 1 then
    vim.cmd("edit " .. files[1])
  else
    require("fzf-lua").files({ cwd = target, prompt = subdir .. " Files> " })
  end
end

function M.find_files_package()
  local pkg = Utils.find_package_root()
  if pkg then
    require("fzf-lua").files({ cwd = pkg, prompt = "Find in Package> " })
  else
    vim.notify("Not inside a ROS 2 package.", vim.log.levels.WARN)
  end
end

function M.grep_package()
  local pkg = Utils.find_package_root()
  if pkg then
    require("fzf-lua").live_grep({ cwd = pkg, prompt = "Grep in Package> " })
  else
    vim.notify("Not inside a ROS 2 package.", vim.log.levels.WARN)
  end
end

return M
