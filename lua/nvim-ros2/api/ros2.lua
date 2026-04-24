local M = {}

function M.list_nodes(cb)
  vim.system({ "ros2", "node", "list" }, { text = true, timeout = 2000 }, function(out)
    vim.schedule(function()
      if out.code ~= 0 or out.stdout == "" then
        cb({})
      else
        cb(vim.split(out.stdout, "\n", { trimempty = true }))
      end
    end)
  end)
end

function M.get_param_metadata(node_name, param_name, cb)
  vim.system(
    { "ros2", "param", "describe", node_name, param_name },
    { text = true, timeout = 2000 },
    function(out)
      vim.schedule(function()
        local meta = {}
        if out.code == 0 then
          local min_val = out.stdout:match("Min value:%s*([%d%.%-]+)")
          local max_val = out.stdout:match("Max value:%s*([%d%.%-]+)")
          if min_val and max_val then
            meta.range = string.format("[%s - %s]", min_val, max_val)
          end
        end
        cb(meta)
      end)
    end
  )
end

function M.get_param(node_name, param_name, cb)
  vim.system(
    { "ros2", "param", "get", node_name, param_name },
    { text = true, timeout = 2000 },
    function(out)
      vim.schedule(function()
        if out.code ~= 0 or out.signal ~= 0 then
          local err = (out.stderr ~= "" and out.stderr) or out.stdout
          if not err:match("Parameter not set") then
            vim.notify("ROS 2 Get Failed: " .. err, vim.log.levels.ERROR)
          end
          return
        end
        local match = out.stdout:match("value is:%s*(.-)%s*\n")
          or out.stdout:match("value is:%s*(.-)%s*$")
        if cb and match then
          cb(match)
        end
      end)
    end
  )
end

function M.set_param(node_name, param_name, value_type, value_text, cb)
  local val = (value_type == "boolean") and value_text:lower() or value_text
  vim.system(
    { "ros2", "param", "set", node_name, param_name, val },
    { text = true, timeout = 2000 },
    function(out)
      vim.schedule(function()
        if out.code ~= 0 or out.signal ~= 0 then
          local err = (out.stderr and out.stderr ~= "") and out.stderr or out.stdout
          vim.notify("ROS 2 Set Failed: " .. err, vim.log.levels.ERROR)
        elseif cb then
          cb()
        else
          vim.notify(string.format("🚀 Tuned! %s = %s", param_name, val), vim.log.levels.INFO)
        end
      end)
    end
  )
end

function M.dump_params(node_name, cb)
  vim.system({ "ros2", "param", "dump", node_name }, { text = true, timeout = 3000 }, function(out)
    vim.schedule(function()
      cb(out.code == 0 and out.stdout or nil)
    end)
  end)
end

return M
