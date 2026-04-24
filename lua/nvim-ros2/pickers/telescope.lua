-- Telescope includes
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local make_entry = require("telescope.make_entry")
local conf = require("telescope.config").values

-- Local previewers
local ros_previewers = require("nvim-ros2.telescope.previewers")

local M = {}

--- Telescope picker to select ROS 2 interfaces
function M.interfaces()
  local command = { "ros2", "interface", "list" }
  local raw_output = nil
  if vim.fn.executable("ros2") == 1 then
    raw_output = vim.fn.systemlist(command)
  else
    vim.notify("ros2 not found", vim.log.levels.ERROR)
    return
  end

  -- Process command output
  local filtered_output = {}
  for _, line in ipairs(raw_output) do
    -- Identify output headers (e.g. "Messages:") to ignore them
    local section_header = line:match("^%s*(%a+):$")
    if not section_header then
      -- trim leading and trailing whitespaces
      local trimmed_line = line:match("^%s*(.-)%s*$")
      if trimmed_line ~= "" then
        table.insert(filtered_output, trimmed_line)
      end
    end
  end
  local opts = {
    preview_title = "Show",
    prompt_title = "Select",
    results_title = "Interfaces",
    filtered_output = filtered_output,
  }
  pickers
    .new(opts, {
      finder = finders.new_table({
        results = opts.filtered_output,
        entry_maker = opts.entry_maker,
      }),
      sorter = conf.generic_sorter(),
      previewer = ros_previewers.preview_interface(),
      dynamic_filter = true,
      attach_mappings = function(_, map)
        -- Disable enter behavior
        map("i", "<CR>", function(_) end)
        map("n", "<CR>", function(_) end)
        return true
      end,
    })
    :find()
end

--- Wrapper for a Telescope picker to select ROS 2 elements
--- Wrapper for a Telescope picker to select ROS 2 elements
local function ros_picker(opts)
  local command_output = nil
  if vim.fn.executable("ros2") == 1 then
    command_output = vim.fn.systemlist(opts.system_cmd)
  else
    vim.notify("ros2 not found", vim.log.levels.ERROR)
    return
  end

  require("telescope.pickers")
    .new(opts, {
      finder = require("telescope.finders").new_table({
        results = command_output,
        entry_maker = opts.entry_maker,
      }),
      sorter = require("telescope.config").values.generic_sorter(),
      previewer = require("nvim-ros2.telescope.previewers").preview_elements(opts),
      dynamic_filter = true,
      attach_mappings = function(prompt_bufnr, map)
        -- Sprint 4: If an on_select callback is provided, override the Enter behavior
        if opts.on_select then
          require("telescope.actions").select_default:replace(function()
            local selection = require("telescope.actions.state").get_selected_entry()
            require("telescope.actions").close(prompt_bufnr)
            -- Return the selected string to the callback
            opts.on_select(selection[1])
          end)
        else
          -- Original behavior: Disable enter behavior for standard info-only viewing
          map("i", "<CR>", function(_) end)
          map("n", "<CR>", function(_) end)
        end
        return true
      end,
    })
    :find()
end

-- Picker of active ROS 2 Nodes
function M.nodes(opts)
  opts = opts or {}
  local system_cmd = { "ros2", "node", "list" }

  -- Merge user-provided opts (like on_select) with the default node configuration
  local node_opts = vim.tbl_extend("force", {
    preview_title = "Node Info",
    prompt_title = "Search",
    results_title = "Active Nodes",
    system_cmd = system_cmd,
    command = "node",
    mode = "info",
    args = "--include-hidden",
  }, opts)

  ros_picker(node_opts)
end

-- Picker of active ROS 2 actions
function M.actions()
  local system_cmd = { "ros2", "action", "list" }

  -- Process command output
  local opts = {
    preview_title = "Action Info",
    prompt_title = "Search",
    results_title = "Active Actions",
    system_cmd = system_cmd,
    command = "action",
    mode = "info",
    args = "--show-types",
  }
  ros_picker(opts)
end

-- Picker of active ROS 2 Services
function M.services()
  local system_cmd = { "ros2", "service", "list" }

  -- Process command output
  local opts = {
    preview_title = "Service Type",
    prompt_title = "Search",
    results_title = "Active Services",
    system_cmd = system_cmd,
    command = "service",
    mode = "type",
    args = "",
  }
  ros_picker(opts)
end

-- Picker of active ROS 2 topics
function M.topics_info()
  local system_cmd = { "ros2", "topic", "list" }

  -- Process command output
  local opts = {
    preview_title = "Topic Info",
    prompt_title = "Search",
    results_title = "Active Topics",
    system_cmd = system_cmd,
    command = "topic",
    mode = "info",
    args = "--verbose",
  }
  ros_picker(opts)
end

function M.topics_echo()
  local system_cmd = { "ros2", "topic", "list" }

  -- Process command output
  local opts = {
    preview_title = "Topic Echo",
    prompt_title = "Search",
    results_title = "Active Topics",
    system_cmd = system_cmd,
    command = "topic",
    mode = "echo",
    args = "--once",
  }
  ros_picker(opts)
end

function M.packages()
  local ws_root = Utils.get_workspace_root(0)
  require("telescope.builtin").find_files({
    prompt_title = "ROS 2 Packages",
    cwd = ws_root,
    find_command = { "fd", "^package.xml$", "--exclude", "build", "--exclude", "install" },
    attach_mappings = function(_, map)
      map("i", "<CR>", function(prompt_bufnr)
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        local pkg_dir = vim.fs.dirname(ws_root .. "/" .. selection.value)
        if pcall(require, "oil") then
          require("oil").open(pkg_dir)
        else
          vim.cmd("edit " .. pkg_dir)
        end
      end)
      return true
    end,
  })
end

function M.sniper(subdir)
  local pkg = Utils.find_package_root()
  if not pkg then
    return
  end
  local target = pkg .. "/" .. subdir

  -- Create dir if missing
  if vim.fn.isdirectory(target) == 0 then
    vim.fn.mkdir(target, "p")
  end

  local files = vim.split(vim.fn.glob(target .. "/*"), "\n", { trimempty = true })
  if #files == 1 then
    vim.cmd("edit " .. files[1])
  else
    require("telescope.builtin").find_files({ cwd = target, prompt_title = subdir .. " Files" })
  end
end

function M.find_files_package()
  local pkg = Utils.find_package_root()
  if pkg then
    require("telescope.builtin").find_files({
      cwd = pkg,
      prompt_title = "Find in Package: " .. vim.fs.basename(pkg),
    })
  else
    vim.notify("Not inside a ROS 2 package.", vim.log.levels.WARN)
  end
end

function M.grep_package()
  local pkg = Utils.find_package_root()
  if pkg then
    require("telescope.builtin").live_grep({
      cwd = pkg,
      prompt_title = "Grep in Package: " .. vim.fs.basename(pkg),
    })
  else
    vim.notify("Not inside a ROS 2 package.", vim.log.levels.WARN)
  end
end

return M
