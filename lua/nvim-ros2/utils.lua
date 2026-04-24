local M = {}

--- Ensures a Fully Qualified Name (FQN) always starts with a slash and has no trailing slashes.
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

--- Extracts the base node name from an FQN (e.g., /namespace/node -> node).
function M.get_base_name(fqn)
  return fqn:match("([^/]+)$") or fqn:gsub("^/", "")
end

--- Locates the root of the ROS 2 workspace (containing .git or package.xml) based on a buffer.
function M.get_workspace_root(bufnr)
  local current_file = vim.api.nvim_buf_get_name(bufnr or 0)
  local search_path = current_file ~= "" and vim.fs.dirname(current_file) or vim.fn.getcwd()
  local root_file = vim.fs.find({ "package.xml", ".git" }, { path = search_path, upward = true })[1]
  return root_file and vim.fs.dirname(root_file) or vim.fn.getcwd()
end

--- Finds the nearest parent directory containing a package.xml.
function M.find_package_root(path)
  path = path or vim.api.nvim_buf_get_name(0)

  -- Handle Oil.nvim buffers
  if path:match("^oil://") then
    path = path:sub(7)
  end
  if path == "" then
    path = vim.fn.getcwd()
  end

  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  if stat and stat.type == "file" then
    path = vim.fs.dirname(path)
  end

  local match = vim.fs.find("package.xml", { path = path, upward = true, type = "file" })[1]
  return match and vim.fs.dirname(match) or nil
end

return M
