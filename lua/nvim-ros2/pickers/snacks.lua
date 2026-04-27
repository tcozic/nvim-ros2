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

  local items = {}
  for _, line in ipairs(output) do
    table.insert(items, { text = line, item = line })
  end

  -- Sprint 5+: Dynamic Custom Actions Mapping
  local win_keys = {}
  local actions = {
    confirm = function(picker, item)
      picker:close()
      if opts.on_select and item then
        opts.on_select(item.text)
      end
    end,
  }

  if opts.custom_actions then
    for key, def in pairs(opts.custom_actions) do
      local action_name = "action_" .. key:gsub("%W", "")
      win_keys[key] = { action_name, mode = { "i", "n" }, desc = def.desc }
      actions[action_name] = function(picker, item)
        picker:close()
        if item and item.text then
          def.callback(item.text)
        end
      end
    end
  end

  Snacks.picker.pick({
    title = opts.prompt_title,
    items = items,
    format = "text",
    win = { input = { keys = win_keys } },
    actions = actions,
    preview = function(ctx)
      local item = ctx.item
      local cmd = { "ros2", opts.command, opts.mode, item.text }
      if opts.args and opts.args ~= "" then
        table.insert(cmd, opts.args)
      end

      ctx.preview:set_lines({ "Loading..." })

      vim.system(cmd, { timeout = opts.timeout or 5000 }, function(result)
        vim.schedule(function()
          pcall(function()
            if result.code == 124 then
              ctx.preview:set_lines({ "Timeout: No data received" })
            elseif result.stdout and result.stdout ~= "" then
              ctx.preview:set_lines(vim.split(result.stdout, "\n", { trimempty = true }))
              ctx.preview:highlight({ lang = "yaml" })
            elseif result.stderr and result.stderr ~= "" then
              ctx.preview:set_lines(vim.split(result.stderr, "\n", { trimempty = true }))
            else
              ctx.preview:set_lines({ "No data" })
            end
          end)
        end)
      end)
    end,
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
        table.insert(items, {
          text = trimmed_line,
          item = trimmed_line,
        })
      end
    end
  end

  Snacks.picker.pick({
    title = "Select Interface",
    items = items,
    format = "text",
    preview = function(ctx)
      local item = ctx.item
      local cmd = { "ros2", "interface", "show", item.text }
      local preview_output = vim.fn.systemlist(cmd)
      ctx.preview:set_lines(preview_output)
      ctx.preview:highlight({ lang = "ros2" })
    end,
    confirm = function() end,
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
    custom_actions = {
      ["<C-t>"] = {
        desc = "Attach ROS Tuner",
        callback = function(node_name)
          if require("nvim-ros2.config").options.tuner then
            require("nvim-ros2.tuner").attach_node(node_name, false)
          else
            vim.notify("ROS Tuner is disabled in config.", vim.log.levels.WARN)
          end
        end,
      },
      ["<C-r>"] = {
        desc = "Attach Scratch Proxy",
        callback = function(node_name)
          if require("nvim-ros2.config").options.tuner then
            require("nvim-ros2.tuner").attach_node(node_name, true)
          end
        end,
      },
    },
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
    timeout = 3000,
  })
end

function M.packages()
  local ws_root = Utils.get_workspace_root(0)

  Snacks.picker.files({
    title = "ROS 2 Packages",
    format = "text",
    cmd = vim.fn.executable("fd") == 1 and "fd" or "find",
    args = vim.fn.executable("fd") == 1
        and { "^package.xml$", "--exclude", "build", "--exclude", "install", "--exclude", "log" }
      or { "-name", "package.xml", "-not", "-path", "*/install/*", "-not", "-path", "*/build/*" },

    transform = function(item)
      local xml_path = item.file
      local pkg_dir = vim.fs.dirname(xml_path)
      local pkg_name = vim.fs.basename(pkg_dir)

      -- Parse XML for actual package name
      local f = io.open(xml_path, "r")
      if f then
        local content = f:read("*a")
        f:close()
        pkg_name = content:match("<name>%s*(.-)%s*</name>") or pkg_name
      end

      item.pkg_dir = pkg_dir
      item.text = pkg_name .. " 📦"
      -- Preview the README if it exists
      for _, v in ipairs({ "/README.md", "/README" }) do
        if vim.uv.fs_stat(pkg_dir .. v) then
          item.file = pkg_dir .. v
          break
        end
      end
      return item
    end,
    actions = {
      confirm = function(picker, item)
        picker:close()
        if item and item.pkg_dir then
          -- Default to Oil if available, else Lexplore
          if pcall(require, "oil") then
            require("oil").open(item.pkg_dir)
          else
            vim.cmd("Lexplore " .. item.pkg_dir)
          end
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
    vim.notify("Created missing directory: " .. subdir, vim.log.levels.INFO)
  end

  local files = vim.split(vim.fn.glob(target .. "/*"), "\n", { trimempty = true })
  if #files == 1 then
    vim.cmd("edit " .. files[1])
  elseif #files > 1 then
    Snacks.picker.files({ cwd = target, title = subdir .. " Files" })
  else
    if pcall(require, "oil") then
      require("oil").open(target)
    else
      vim.cmd("Lexplore " .. target)
    end
  end
end

function M.find_files_package()
  local pkg = Utils.find_package_root()
  if pkg then
    Snacks.picker.files({
      cwd = pkg,
      title = "Find in Package: " .. vim.fs.basename(pkg),
    })
  else
    vim.notify("Not inside a ROS 2 package.", vim.log.levels.WARN)
  end
end

function M.grep_package()
  local pkg = Utils.find_package_root()
  if pkg then
    Snacks.picker.grep({
      cwd = pkg,
      title = "Grep in Package: " .. vim.fs.basename(pkg),
    })
  else
    vim.notify("Not inside a ROS 2 package.", vim.log.levels.WARN)
  end
end

return M
