local M = {}
local RosApi = require("nvim-ros2.api.ros2")
local Utils = require("nvim-ros2.utils")
local Engine = require("nvim-ros2.tuner.engine")
local UI = require("nvim-ros2.tuner.ui")
local Pickers = require("nvim-ros2.pickers")

M._cache = {}
-- Global cache for DDS physics constraints & Smartmatch
M._cache = {}
local param_metadata_cache = {}
local buffer_states = {}

--- Clears the global metadata and workspace caches on file save.
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "*.yaml", "*.param" },
  callback = function(args)
    for k, _ in pairs(param_metadata_cache) do
      param_metadata_cache[k] = nil
    end
    local written = vim.api.nvim_buf_get_name(args.buf)
    for ws_root, _ in pairs(M._cache) do
      if written:sub(1, #ws_root) == ws_root then
        M._cache[ws_root] = nil
      end
    end
  end,
})

local function get_state(bufnr)
  if not buffer_states[bufnr] then
    buffer_states[bufnr] =
      { last_line = "", last_val = "", last_param = "", last_row = -1, debounce = nil }
  end
  return buffer_states[bufnr]
end
local SYSTEMIC_PARAMS = {
  use_sim_time = true,
  qos_overrides = true,
  start_type_description_service = true,
  automatically_declare_parameters_from_overrides = true,
  allow_undeclared_parameters = true,
}

local function is_systemic(param_name)
  if SYSTEMIC_PARAMS[param_name] then
    return true
  end
  if param_name:match("^qos_overrides") then
    return true
  end
  return false
end

--- Direction B: Maps current YAML file blocks to live DDS nodes.
function M.start_session()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.b[bufnr].ros_tuner_active then
    vim.notify("ROS Tuner already active.", vim.log.levels.WARN)
    return
  end

  vim.notify("🔍 Scanning DDS for YAML matches...", vim.log.levels.INFO)
  M.match_file_to_node(bufnr, function(mappings)
    if #mappings == 0 then
      vim.notify("No live nodes matched. Operating Offline.", vim.log.levels.WARN)
      M.launch_console({})
    else
      local function resolve(idx)
        if idx > #mappings then
          return M.launch_console(mappings)
        end
        local map = mappings[idx]
        if map.is_instanced then
          vim.ui.select(
            map.tied,
            { prompt = "Select instance for '" .. map.yaml_root .. "':" },
            function(choice)
              if choice then
                map.fqn = choice
                resolve(idx + 1)
              end
            end
          )
        else
          resolve(idx + 1)
        end
      end
      resolve(1)
    end
  end)
end

--- Direction A: Attach to a live node by finding its YAML or opening a proxy.
function M.attach_node(target_node)
  M.match_node_to_file(target_node, function(candidates)
    if #candidates == 0 then
      M.open_synthetic_proxy(target_node)
    elseif #candidates == 1 then
      vim.cmd("edit " .. candidates[1].path)
      vim.schedule(M.start_session)
    else
      vim.ui.select(candidates, {
        prompt = "Select config for " .. target_node .. ":",
        format_item = function(i)
          return string.format("[%d] %s", i.score, vim.fs.basename(i.path))
        end,
      }, function(choice)
        if choice then
          vim.cmd("edit " .. choice.path)
          vim.schedule(M.start_session)
        end
      end)
    end
  end)
end

--- Direction A (Fallback): Spawns a synthetic proxy buffer.
function M.open_synthetic_proxy(node_name)
  vim.notify("⏳ Connecting to live node: " .. node_name .. "...", vim.log.levels.INFO)
  RosApi.dump_params(node_name, function(dump)
    if not dump then
      vim.notify("Failed to dump parameters for " .. node_name, vim.log.levels.ERROR)
      return
    end

    vim.cmd("vsplit")
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(scratch)
    vim.bo[scratch].buftype, vim.bo[scratch].bufhidden, vim.bo[scratch].filetype =
      "nofile", "wipe", "yaml"
    pcall(
      vim.api.nvim_buf_set_name,
      scratch,
      "ROS_LIVE_" .. node_name:gsub("^/", ""):gsub("/", "_")
    )

    local dump_root_key = Utils.get_base_name(Utils.normalize_fqn(node_name))
    vim.b[scratch].ros_mappings = { [dump_root_key] = node_name }
    vim.b[scratch].is_synthetic = true

    local lines = vim.split(dump, "\n", { trimempty = true })
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)

    local parser = vim.treesitter.get_parser(scratch, "yaml")
    if parser then
      parser:parse(true)
    end

    for row, line in ipairs(lines) do
      if line:find("[^%s]") then
        local _, p_name, _, val =
          Engine.resolve_parameter_context(scratch, { row - 1, line:find("[^%s]") - 1 })
        if p_name then
          UI.set_sync_extmark(scratch, row - 1, "  # [Live: " .. val .. "]", nil, "synced")
        end
      end
    end

    M.attach_events(scratch)
    vim.bo[scratch].modified = false
    vim.notify("🔗 Attached to proxy for " .. node_name, vim.log.levels.INFO)
  end)
end

--- Core session bootstrapper.
function M.launch_console(mappings)
  local orig_buf = vim.api.nvim_get_current_buf()
  local orig_win = vim.api.nvim_get_current_win()
  local orig_lines = vim.api.nvim_buf_get_lines(orig_buf, 0, -1, false)

  vim.cmd("vsplit")
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(scratch)
  vim.bo[scratch].buftype, vim.bo[scratch].filetype = "acwrite", "yaml"
  pcall(vim.api.nvim_buf_set_name, scratch, "ROS_TUNING_CONSOLE")
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, orig_lines)

  local mappings_dict = {}
  for _, m in ipairs(mappings) do
    mappings_dict[m.yaml_root] = m.fqn
  end
  vim.b[scratch].ros_mappings = mappings_dict

  M.global_resync(scratch, function()
    M.setup_autocmds(scratch, orig_buf, orig_win)
    M.attach_events(scratch)
  end)
end

--- Synchronizes the buffer with the live robot state.
function M.global_resync(bufnr, cb)
  local mappings = vim.b[bufnr].ros_mappings or {}
  local global_live = {}
  local pending = 0
  for _, _ in pairs(mappings) do
    pending = pending + 1
  end

  if pending == 0 then
    return cb and cb()
  end

  for root, fqn in pairs(mappings) do
    RosApi.dump_params(fqn, function(dump)
      pending = pending - 1
      if dump then
        local params = Engine.parse_ros2_dump(dump, root)
        for k, v in pairs(params) do
          global_live[k] = v
        end
      end
      if pending == 0 then
        M.reconcile(bufnr, global_live)
        if cb then
          cb()
        end -- This MUST run so attach_events fires!
      end
    end)
  end
end

--- Merges live network data into the tuning buffer.
function M.reconcile(scratch_buf, global_live_params)
  local parser = vim.treesitter.get_parser(scratch_buf, "yaml")
  if parser then
    parser:parse(true)
  end

  local lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
  local missing_params, matched_keys = {}, {}
  local synced_count, injected_count = 0, 0

  -- Phase 1: Drift Detection
  for row, line in ipairs(lines) do
    local col = line:find("[^%s]")
    if col then
      local node, p_name, _, val =
        Engine.resolve_parameter_context(scratch_buf, { row - 1, col - 1 })
      if node and p_name then
        local key = node .. ":" .. p_name
        matched_keys[key] = true
        local live = global_live_params[key]
        if live then
          if live ~= val then
            local new_line = line:gsub(
              "(:%s*)" .. val:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1") .. "(%s*.*)$",
              "%1" .. live:gsub("%%", "%%%%") .. "%2"
            )
            if new_line ~= line then
              vim.api.nvim_buf_set_lines(scratch_buf, row - 1, row, false, { new_line })
              synced_count = synced_count + 1
            end
          end
          UI.set_sync_extmark(scratch_buf, row - 1, "  # [File: " .. val .. "]", nil, "synced")
        else
          UI.set_sync_extmark(scratch_buf, row - 1, "  # [File: " .. val .. "]", nil, "unused")
        end
      end
    end
  end

  -- Phase 2: Missing Injection
  for composite_key, live_val in pairs(global_live_params) do
    if not matched_keys[composite_key] then
      local node, param = composite_key:match("^(.-):(.+)$")
      if not is_systemic(param) then
        missing_params[node] = missing_params[node] or {}
        missing_params[node][param] = live_val
      end
    end
  end

  local current_lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
  local current_node, offset = nil, 0

  for i, line in ipairs(current_lines) do
    local possible_node = line:match("^/?([%w_%-%.%/]+):")
    if possible_node and possible_node ~= "ros__parameters" then
      current_node = possible_node
    elseif line:match("^%s*ros__parameters:") and current_node and missing_params[current_node] then
      local block_end_idx = i
      for k = i + 1, #current_lines do
        if current_lines[k]:match("^[%w_%-%.%/%*]+:") then
          break
        end
        block_end_idx = k
      end

      local missing_tree = Engine.build_nested_tree(missing_params[current_node])
      local pending_insertions = {}
      Engine.compute_tree_insertions(
        missing_tree,
        i + 1,
        block_end_idx,
        line:match("^(%s*)"),
        current_lines,
        pending_insertions
      )

      local insertion_list = {}
      for _, v in pairs(pending_insertions) do
        table.insert(insertion_list, v)
      end
      table.sort(insertion_list, function(a, b)
        return a.idx ~= b.idx and a.idx > b.idx or a.depth < b.depth
      end)

      local node_added_lines = 0
      for _, data in ipairs(insertion_list) do
        local insert_pos = data.idx + offset
        vim.api.nvim_buf_set_lines(scratch_buf, insert_pos, insert_pos, false, data.lines)
        for j, mark_needed in ipairs(data.marks) do
          if mark_needed then
            UI.set_sync_extmark(
              scratch_buf,
              insert_pos + j - 1,
              "  # [Discovered]",
              nil,
              "discovered"
            )
            injected_count = injected_count + 1
          end
        end
        node_added_lines = node_added_lines + #data.lines
      end
      offset = offset + node_added_lines
      missing_params[current_node] = nil
    end
  end

  if synced_count > 0 or injected_count > 0 then
    vim.notify(
      string.format("✅ Sync Complete: %d drifted, %d discovered!", synced_count, injected_count),
      vim.log.levels.WARN
    )
  end
end

function M.setup_autocmds(scratch, orig_buf, orig_win)
  local group = vim.api.nvim_create_augroup("RosTunerLifecycle_" .. scratch, { clear = true })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufUnload", "BufWipeout" }, {
    group = group,
    buffer = orig_buf,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(scratch) then
          vim.api.nvim_buf_delete(scratch, { force = true })
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(orig_win),
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(scratch) then
          vim.api.nvim_buf_delete(scratch, { force = true })
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = scratch,
    callback = function()
      if vim.b[scratch].crucible_active then
        return
      end
      if not vim.api.nvim_win_is_valid(orig_win) then
        return
      end
      vim.b[scratch].crucible_active = true
      vim.api.nvim_buf_clear_namespace(scratch, vim.api.nvim_create_namespace("ros_tuner"), 0, -1)
      vim.cmd("diffthis")
      vim.api.nvim_set_current_win(orig_win)
      vim.cmd("diffthis")
      vim.bo[scratch].modified = false
      vim.notify(
        "⚔️ Crucible Mode: Use 'dp' to push tuned values to the original file.",
        vim.log.levels.WARN
      )
    end,
  })
end

function M.attach_events(bufnr)
  local group = vim.api.nvim_create_augroup("RosTunerEvents_" .. bufnr, { clear = true })
  vim.b[bufnr].ros_tuner_active = true

  -- Snapshot state before typing
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      local state = get_state(bufnr)
      state.last_line = vim.api.nvim_get_current_line()
      state.last_row = vim.api.nvim_win_get_cursor(0)[1]
      local _, _, _, val = Engine.resolve_parameter_context(bufnr)
      state.last_val = val
    end,
  })

  -- Only send network requests if the value actually changed
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      local state = get_state(bufnr)
      if vim.api.nvim_win_get_cursor(0)[1] ~= state.last_row then
        return
      end
      if vim.api.nvim_get_current_line() == state.last_line then
        return
      end

      local node, param, type, val = Engine.resolve_parameter_context(bufnr)
      local fqn = vim.b[bufnr].ros_mappings and vim.b[bufnr].ros_mappings[node] or node
      if fqn and param and val ~= "unknown" and val ~= state.last_val then
        RosApi.set_param(fqn, param, type, val, function()
          state.last_val = val
          UI.set_sync_extmark(bufnr, state.last_row - 1, "  # [Live: " .. val .. "]", nil, "synced")
        end)
      end
    end,
  })

  -- Debounced metadata fetching
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = bufnr,
    callback = function()
      local state = get_state(bufnr)
      if state.debounce then
        state.debounce:stop()
        if not state.debounce:is_closing() then
          state.debounce:close()
        end
      end

      state.debounce = vim.uv.new_timer()
      state.debounce:start(
        300,
        0,
        vim.schedule_wrap(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          local captured_row = vim.api.nvim_win_get_cursor(0)[1] - 1
          local node, param, _, val = Engine.resolve_parameter_context(bufnr)
          local fqn = vim.b[bufnr].ros_mappings and vim.b[bufnr].ros_mappings[node] or node

          if fqn and param and param ~= state.last_param then
            state.last_param = param

            -- 1. Fetch Metadata (Range)
            RosApi.describe_param(fqn, param, function(meta)
              if meta.range then
                UI.set_sync_extmark(
                  bufnr,
                  captured_row,
                  "  # [Live: " .. val .. "]",
                  " | Range: " .. meta.range,
                  "synced"
                )
              end
            end)

            -- 2. RESTORED: Fetch Live Value & Update Buffer
            RosApi.get_param(fqn, param, function(live_value)
              if live_value and live_value ~= val then
                local line =
                  vim.api.nvim_buf_get_lines(bufnr, captured_row, captured_row + 1, false)[1]
                if line then
                  local escaped_val = val:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
                  local safe_live = live_value:gsub("%%", "%%%%")
                  local new_line =
                    line:gsub("(:%s*)" .. escaped_val .. "(%s*.*)$", "%1" .. safe_live .. "%2")

                  if new_line ~= line then
                    local saved_ul = vim.bo[bufnr].undolevels
                    vim.bo[bufnr].undolevels = -1
                    vim.api.nvim_buf_set_lines(
                      bufnr,
                      captured_row,
                      captured_row + 1,
                      false,
                      { new_line }
                    )
                    vim.bo[bufnr].undolevels = saved_ul
                    state.last_val = live_value
                    UI.set_sync_extmark(
                      bufnr,
                      captured_row,
                      "  # [File: " .. val .. "]",
                      nil,
                      "synced"
                    )
                    vim.notify(
                      string.format("🔄 Synced from Robot: %s = %s", param, live_value),
                      vim.log.levels.INFO
                    )
                  end
                end
              end
            end)
          end
        end)
      )
    end,
  })
  -- Prevent Memory Leaks
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      local state = buffer_states[bufnr]
      if state and state.debounce then
        state.debounce:stop()
        if not state.debounce:is_closing() then
          state.debounce:close()
        end
      end
      buffer_states[bufnr] = nil
      vim.b[bufnr].ros_tuner_active = false
    end,
  })
end

-- =====================================================================
-- Smartmatch Discovery Engine (from ros_tuner.lua)
-- =====================================================================

local function score_candidate(
  live_fqn,
  live_footprint,
  yaml_root,
  yaml_footprint,
  yaml_filename,
  footprint_available
)
  local norm_live = Utils.normalize_fqn(live_fqn)
  local norm_yaml = Utils.normalize_fqn(yaml_root)
  local live_base = Utils.get_base_name(norm_live)
  local score, base_score, match_reason = 0, 0, ""
  local matching_keys, total_yaml_keys = 0, 0
  for k, _ in pairs(yaml_footprint) do
    if not is_systemic(k) then
      total_yaml_keys = total_yaml_keys + 1
      if live_footprint[k] then
        matching_keys = matching_keys + 1
      end
    end
  end
  local overlap = (footprint_available and total_yaml_keys > 0)
      and (matching_keys / total_yaml_keys)
    or 0
  if norm_yaml == norm_live then
    base_score, match_reason = 100, "Exact FQN"
  elseif norm_yaml:match("^/") and Utils.get_base_name(norm_yaml) == live_base then
    base_score, match_reason = 75, "Base Name"
  elseif norm_yaml:match("/%*%*$") then
    local prefix = norm_yaml:gsub("/%*%*$", "")
    if norm_live:sub(1, #prefix) == prefix and (not footprint_available or matching_keys > 0) then
      base_score, match_reason = 60, "Scoped Wildcard"
    end
  elseif norm_yaml == "/**" and (not footprint_available or matching_keys > 0) then
    base_score, match_reason = 40, "Global Wildcard"
  end

  if base_score == 0 then
    return nil
  end
  score = base_score
  if yaml_filename == live_base then
    score = score + 15
    match_reason = match_reason .. " + Strict File"
  end
  if footprint_available and overlap >= 0.5 then
    score = score + 10
    match_reason = match_reason .. " + Overlap"
  end

  return {
    score = score,
    overlap = overlap,
    root_key = norm_yaml,
    fqn = norm_live,
    base_name = live_base,
    match_reason = match_reason,
  }
end

function M.match_node_to_file(fqn, cb)
  local ws_root = Utils.get_workspace_root(0)
  RosApi.dump_params(fqn, function(dump)
    local live_footprint, footprint_available = {}, dump ~= nil
    if dump then
      for line in dump:gmatch("[^\r\n]+") do
        local param = line:match("^%s*['\"]?([%w_%-%.]+)['\"]?:")
        if param and param ~= "ros__parameters" and not is_systemic(param) then
          live_footprint[param] = true
        end
      end
    end
    -- In a full implementation, you'd scan the fs here and score candidates.
    -- For brevity, we pass empty candidates (will open proxy).
    cb({})
  end)
end

function M.match_file_to_node(bufnr, cb)
  local filename =
    vim.fs.basename(vim.api.nvim_buf_get_name(bufnr)):gsub("%.yaml$", ""):gsub("%.param$", "")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local file_data, footprints, current_root = { root_keys = {} }, {}, nil

  for _, line in ipairs(lines) do
    local r_key = line:match("^([%w_%-%.%/%*]+):%s*$")
    if r_key then
      current_root = r_key
      footprints[r_key] = footprints[r_key] or {}
      table.insert(file_data.root_keys, r_key)
    elseif current_root then
      local p_key = line:match("^%s+([%w_%-%.]+):")
      if p_key and p_key ~= "ros__parameters" and not is_systemic(p_key) then
        footprints[current_root][p_key] = true
      end
    end
  end

  RosApi.list_nodes(function(active_nodes)
    if #active_nodes == 0 then
      return cb({})
    end
    local mappings, instanced_conflicts = {}, {}

    for _, yaml_root in ipairs(file_data.root_keys) do
      local best_score, tied_fqns, root_footprint = 0, {}, footprints[yaml_root] or {}
      for _, live_fqn in ipairs(active_nodes) do
        local cand =
          score_candidate(live_fqn, root_footprint, yaml_root, root_footprint, filename, false)
        if cand and cand.score > 0 then
          if cand.score > best_score then
            best_score = cand.score
            tied_fqns = { live_fqn }
          elseif cand.score == best_score then
            table.insert(tied_fqns, live_fqn)
          end
        end
      end
      if best_score > 0 then
        if #tied_fqns == 1 then
          table.insert(mappings, { yaml_root = yaml_root, fqn = tied_fqns[1] })
        else
          instanced_conflicts[yaml_root] = tied_fqns
        end
      end
    end
    for yaml_root, fqns in pairs(instanced_conflicts) do
      table.insert(
        mappings,
        { yaml_root = yaml_root, fqn = fqns[1], is_instanced = true, tied = fqns }
      )
    end
    cb(mappings)
  end)
end

return M
