# 🎮 🐢 nvim-ros2

**nvim-ros2** is a simple lua plugin that adds useful features to enhance your development workflow
while developing ROS 2 modules.

> **🌿 Fork Notice:** This repository is a feature-rich fork of the excellent [nvim-ros2 plugin by Erick Kramer](https://github.com/erickkramer/nvim-ros2). 
> 
> **Why use this fork?** It introduces two massive capabilities: the **ROS 2 Tuner** (a hardware-in-the-loop live parameter tuning engine) and the **Workspace Navigator** (package-scoped pickers). These features have been submitted upstream via a Pull Request, but you can use this fork directly in the meantime!

## 🪄 Features

### 🌳 Treesitter Parser

- Custom grammar with syntax [highlights](./queries/ros2/highlights.scm) for [ROS 2 interfaces](https://docs.ros.org/en/humble/Concepts/Basic/About-Interfaces.html) following official conventions.
- After configuring the plugin, the grammar can be installed using `TSInstall ros2`

#### ✨ Highlights Examples

- `.msg` file

![ROS 2 msg](./assets/ros2_msg.png)

- `.srv` file

![ROS 2 srv](./assets/ros2_srv.png)

- `.action` file

![ROS 2 action](./assets/ros2_action.png)

### 🔭 Telescope

- [Telescope](https://github.com/nvim-telescope/telescope.nvim) extension that adds pickers for ROS 2 components

#### Active Actions with info preview

![telescope actions](./assets/actions.gif)

#### Active interfaces with show preview

![telescope interfaces](./assets/interfaces.gif)

#### Active Nodes with info preview

![telescope nodes](./assets/nodes.gif)

#### Active Services with type preview

![telescope services](./assets/services.gif)

#### Active topics with info preview

![telescope topics_info](./assets/topics.gif)

### Autocommands

- Configure `*.action`, `*.msg`, and `*.srv` files as `ros` filetype
- Configure `*.launch`, `*.xacro`, and `*.urdf` files as `xml` filetype


### 🧭 Workspace Navigator

Package-aware pickers designed to scope your searches to the specific ROS 2 package you are currently editing. Available across Telescope, Snacks, and Fzf-lua.

- **Scoped Searches:** Find files or live grep exclusively within the boundaries of the active package.
- **Package Hub:** List all ROS 2 packages in your workspace and open them in your file explorer.
- **Quick-Edits:** Instantly jump to the `CMakeLists.txt` or `package.xml` of your current package.
- **Snipers:** Fast directory navigation to jump directly into `msg/`, `srv/`, `action/`, or `include/` folders.
- **Smart Attach:** Press `<C-t>` while hovering over a node in the Active Nodes picker to instantly attach the ROS Tuner.

### 🎛️ ROS 2 Tuner

A hardware-in-the-loop tuning engine to safely synchronize local parameter files (`.yaml` / `.param`) with live DDS nodes on your robot. 

- **Direction A (Attach Proxy):** Run `:RosTune attach <node>` to spawn a synthetic, temporary YAML buffer perfectly synced to the live node.
- **Direction B (Smartmatch):** Open any local parameter file and run `:RosTune`. The algorithmic engine scans the DDS network, fuzzily matches your YAML keys to active nodes, and spawns a Tuning Console.
- **Direction C (Crucible Mode):** After experimenting with live values in the Tuning Console, simply save the file (`:w`). Both the console and your original file will enter Neovim's `diffthis` mode, allowing you to selectively push (`dp`) your tuned values back to the source code.
- **Live Event Loop:** Values and boundaries (Ranges) are dynamically fetched as virtual text. Modifying a value in Insert mode safely triggers a `ros2 param set` network call in the background.

#### 📊 Statusline Integration
You can expose the buffer's tuning health (synced, unused, or offline parameters) directly in your statusline (e.g., Lualine):
```lua
require("lualine").setup({
  sections = {
    lualine_x = { require("nvim-ros2").tuner_status },
  }
})
```

## 🧰 Installation

## Configuration

### Lazy.nvim

#### Default (Telescope)

```lua
return {
  "tcozic/nvim-ros2",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    picker = "telescope",
    autocmds = true,
    treesitter = true,
    tuner = true, -- Enables the :RosTune command and hardware proxy
    tuner_match_mode = "smart", -- "smart" (algorithm), "simple" (root keys), or "all" (skip filter)
  },
  keys = {
    -- Base Pickers
    { "<leader>li", function() require("nvim-ros2").pickers.interfaces() end, desc = "[ROS 2]: List interfaces" },
    { "<leader>ln", function() require("nvim-ros2").pickers.nodes() end, desc = "[ROS 2]: List nodes" },
    { "<leader>la", function() require("nvim-ros2").pickers.actions() end, desc = "[ROS 2]: List actions" },
    { "<leader>lt", function() require("nvim-ros2").pickers.topics_info() end, desc = "[ROS 2]: List topics with info" },
    { "<leader>le", function() require("nvim-ros2").pickers.topics_echo() end, desc = "[ROS 2]: List topics with echo" },
    { "<leader>ls", function() require("nvim-ros2").pickers.services() end, desc = "[ROS 2]: List services" },
    
    -- Workspace Navigator
    { "<leader>fp", function() require("nvim-ros2").pickers.packages() end, desc = "[F]ind ROS2 [P]ackage" },
    { "<leader>pf", function() require("nvim-ros2").pickers.find_files_package() end, desc = "Find in Package" },
    { "<leader>pg", function() require("nvim-ros2").pickers.grep_package() end, desc = "Grep in Package" },
    { "<leader>pc", function() require("nvim-ros2").pickers.edit_cmake() end, desc = "Edit CMakeLists.txt" },
    { "<leader>pp", function() require("nvim-ros2").pickers.edit_package_xml() end, desc = "Edit package.xml" },
    
    -- Snipers
    { "<leader>pm", function() require("nvim-ros2").pickers.sniper("msg") end, desc = "Sniper: msg/" },
    { "<leader>ps", function() require("nvim-ros2").pickers.sniper("srv") end, desc = "Sniper: srv/" },
    { "<leader>pa", function() require("nvim-ros2").pickers.sniper("action") end, desc = "Sniper: action/" },
    { "<leader>pi", function() require("nvim-ros2").pickers.sniper("include") end, desc = "Sniper: include/" },

    -- Tuner
    { "<leader>rt", "<cmd>RosTune<cr>", desc = "Start ROS Tuner" },
  },
}
```

#### Snacks.nvim

```lua
return {
  "tcozic/nvim-ros2",
  dependencies = {
    "folke/snacks.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    picker = "snacks",
    autocmds = true,
    treesitter = true,
    tuner = true,
    tuner_match_mode = "smart",
  },
  keys = {
    -- Base Pickers
    { "<leader>li", function() require("nvim-ros2").pickers.interfaces() end, desc = "[ROS 2]: List interfaces" },
    { "<leader>ln", function() require("nvim-ros2").pickers.nodes() end, desc = "[ROS 2]: List nodes" },
    { "<leader>la", function() require("nvim-ros2").pickers.actions() end, desc = "[ROS 2]: List actions" },
    { "<leader>lt", function() require("nvim-ros2").pickers.topics_info() end, desc = "[ROS 2]: List topics with info" },
    { "<leader>le", function() require("nvim-ros2").pickers.topics_echo() end, desc = "[ROS 2]: List topics with echo" },
    { "<leader>ls", function() require("nvim-ros2").pickers.services() end, desc = "[ROS 2]: List services" },
    
    -- Workspace Navigator
    { "<leader>fp", function() require("nvim-ros2").pickers.packages() end, desc = "[F]ind ROS2 [P]ackage" },
    { "<leader>pf", function() require("nvim-ros2").pickers.find_files_package() end, desc = "Find in Package" },
    { "<leader>pg", function() require("nvim-ros2").pickers.grep_package() end, desc = "Grep in Package" },
    { "<leader>pc", function() require("nvim-ros2").pickers.edit_cmake() end, desc = "Edit CMakeLists.txt" },
    { "<leader>pp", function() require("nvim-ros2").pickers.edit_package_xml() end, desc = "Edit package.xml" },
    
    -- Snipers
    { "<leader>pm", function() require("nvim-ros2").pickers.sniper("msg") end, desc = "Sniper: msg/" },
    { "<leader>ps", function() require("nvim-ros2").pickers.sniper("srv") end, desc = "Sniper: srv/" },
    { "<leader>pa", function() require("nvim-ros2").pickers.sniper("action") end, desc = "Sniper: action/" },
    { "<leader>pi", function() require("nvim-ros2").pickers.sniper("include") end, desc = "Sniper: include/" },

    -- Tuner
    { "<leader>rt", "<cmd>RosTune<cr>", desc = "Start ROS Tuner" },
  },
}
```

#### Fzf-lua

```lua
return {
  "tcozic/nvim-ros2",
  dependencies = {
    "ibhagwan/fzf-lua",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    picker = "fzf",
    autocmds = true,
    treesitter = true,
    tuner = true,
    tuner_match_mode = "smart",
  },
  keys = {
    -- Base Pickers
    { "<leader>li", function() require("nvim-ros2").pickers.interfaces() end, desc = "[ROS 2]: List interfaces" },
    { "<leader>ln", function() require("nvim-ros2").pickers.nodes() end, desc = "[ROS 2]: List nodes" },
    { "<leader>la", function() require("nvim-ros2").pickers.actions() end, desc = "[ROS 2]: List actions" },
    { "<leader>lt", function() require("nvim-ros2").pickers.topics_info() end, desc = "[ROS 2]: List topics with info" },
    { "<leader>le", function() require("nvim-ros2").pickers.topics_echo() end, desc = "[ROS 2]: List topics with echo" },
    { "<leader>ls", function() require("nvim-ros2").pickers.services() end, desc = "[ROS 2]: List services" },
    
    -- Workspace Navigator
    { "<leader>fp", function() require("nvim-ros2").pickers.packages() end, desc = "[F]ind ROS2 [P]ackage" },
    { "<leader>pf", function() require("nvim-ros2").pickers.find_files_package() end, desc = "Find in Package" },
    { "<leader>pg", function() require("nvim-ros2").pickers.grep_package() end, desc = "Grep in Package" },
    { "<leader>pc", function() require("nvim-ros2").pickers.edit_cmake() end, desc = "Edit CMakeLists.txt" },
    { "<leader>pp", function() require("nvim-ros2").pickers.edit_package_xml() end, desc = "Edit package.xml" },
    
    -- Snipers
    { "<leader>pm", function() require("nvim-ros2").pickers.sniper("msg") end, desc = "Sniper: msg/" },
    { "<leader>ps", function() require("nvim-ros2").pickers.sniper("srv") end, desc = "Sniper: srv/" },
    { "<leader>pa", function() require("nvim-ros2").pickers.sniper("action") end, desc = "Sniper: action/" },
    { "<leader>pi", function() require("nvim-ros2").pickers.sniper("include") end, desc = "Sniper: include/" },

    -- Tuner
    { "<leader>rt", "<cmd>RosTune<cr>", desc = "Start ROS Tuner" },
  },
}
```

## Related Projects

- [taDachs/ros-nvim](https://github.com/taDachs/ros-nvim)
- [thibthib18/ros-nvim](https://github.com/thibthib18/ros-nvim)

## Disclaimer

The functionalities here provided were validated using [ROS 2 humble](https://docs.ros.org/en/humble/index.html).

![ROS humble](https://docs.ros.org/en/humble/_static/humble-small.png)
