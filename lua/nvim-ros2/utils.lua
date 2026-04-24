local M = {}

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

--- Locates the root of the ROS 2 workspace prioritizing package.xml over .git
function M.get_workspace_root(bufnr)
  local current_file = vim.api.nvim_buf_get_name(bufnr or 0)
  local search_path = current_file ~= "" and vim.fs.dirname(current_file) or vim.fn.getcwd()

  local pkg = vim.fs.find("package.xml", { path = search_path, upward = true })[1]
  if pkg then
    return vim.fs.dirname(pkg)
  end

  local git = vim.fs.find(".git", { path = search_path, upward = true })[1]
  if git then
    return vim.fs.dirname(git)
  end

  return vim.fn.getcwd()
end

function M.find_package_root(path)
  path = path or vim.api.nvim_buf_get_name(0)
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
