-- lua/nvim-ros2/utils.lua

local M = {}

-- Private Helper: Handles both Buffer IDs and String Paths (like oil://)
local function get_search_path(target)
  local path = ""
  if type(target) == "string" then
    path = target
    if path:match("^oil://") then
      path = path:sub(7)
    end
  else
    path = vim.api.nvim_buf_get_name(target or 0)
  end

  if path == "" then
    return vim.fn.getcwd()
  end

  -- If it's a directory (like from Oil), return it directly. Otherwise, get the parent.
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "directory" then
    return path
  end
  return vim.fs.dirname(path)
end

function M.normalize_fqn(name)
  if not name then
    return ""
  end
  name = name:match("^%s*(.-)%s*$")
  if not name:match("^/") then
    name = "/" .. name
  end
  return name:gsub("/+$", "")
end

function M.get_base_name(fqn)
  return fqn:match("([^/]+)$") or fqn:gsub("^/", "")
end

--- Locates the root of the ROS 2 workspace robustly.
--- Scans upwards checking for the parallel existence of src/ and either build/ or install/
function M.get_workspace_root(target)
  local search_path = get_search_path(target)
  local current = search_path

  while current and current ~= "/" do
    local has_build = vim.uv.fs_stat(current .. "/build")
    local has_install = vim.uv.fs_stat(current .. "/install")
    local has_src = vim.uv.fs_stat(current .. "/src")

    if (has_build or has_install) and has_src then
      return current
    end
    current = vim.fs.dirname(current)
  end

  -- Fallback to package root if not in a standard Colcon workspace
  return M.get_package_root(target)
end

--- 📦 PACKAGE FINDER: Locates the specific package root (where package.xml lives).
function M.get_package_root(target)
  local search_path = get_search_path(target)

  local root = vim.fs.find({ "package.xml", ".git" }, {
    path = search_path,
    upward = true,
  })[1]

  return root and vim.fs.dirname(root) or vim.fn.getcwd()
end

M.find_package_root = M.get_package_root

--- Scans the workspace and returns a table mapping ROS 2 package names to their directory paths.
function M.get_workspace_packages(ws_root)
  local packages = {}
  if not ws_root then
    return packages
  end

  local cmd = vim.fn.executable("fd") == 1
      and {
        "fd",
        "-t",
        "f",
        "^package.xml$",
        ws_root,
        "-E",
        "build/",
        "-E",
        "install/",
        "-E",
        "log/",
      }
    or {
      "find",
      ws_root,
      "-type",
      "f",
      "-name",
      "package.xml",
      "-not",
      "-path",
      "*/build/*",
      "-not",
      "-path",
      "*/install/*",
      "-not",
      "-path",
      "*/log/*",
    }

  local xml_files = vim.fn.systemlist(cmd)

  for _, xml_path in ipairs(xml_files) do
    local pkg_dir = vim.fs.dirname(xml_path)
    local pkg_name = vim.fs.basename(pkg_dir)

    -- Parse XML for the true package name
    local f = io.open(xml_path, "r")
    if f then
      local content = f:read("*a")
      f:close()
      pkg_name = content:match("<name>%s*(.-)%s*</name>") or pkg_name
    end

    packages[pkg_name] = pkg_dir
  end

  return packages
end

return M
