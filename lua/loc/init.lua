local M = {}

local defaults = {
  auto_enable = true,
  persist = true,
  data_path = nil,
  save_delay_ms = 1000,
  statusline_prefix = "LOC",
}

local state = {
  config = nil,
  loaded = false,
  loaded_path = nil,
  enabled = false,
  augroup = nil,
  snapshots = {},
  save_pending = false,
  dirty = false,
  added = 0,
  deleted = 0,
}

local function data_path()
  if state.config and state.config.data_path then
    return state.config.data_path
  end

  return table.concat({ vim.fn.stdpath("data"), "loc.nvim", "stats.json" }, "/")
end

local function json_encode(value)
  if vim.json and vim.json.encode then
    return vim.json.encode(value)
  end

  return vim.fn.json_encode(value)
end

local function json_decode(value)
  if vim.json and vim.json.decode then
    return vim.json.decode(value)
  end

  return vim.fn.json_decode(value)
end

local function char_count(value)
  if value == "" then
    return 0
  end

  local ok, count = pcall(vim.fn.strchars, value)
  if ok then
    return count
  end

  return #value
end

local function is_continuation_byte(byte)
  return byte and byte >= 0x80 and byte <= 0xbf
end

local function has_char_boundary_after(value, byte_index)
  if byte_index <= 0 or byte_index >= #value then
    return true
  end

  return not is_continuation_byte(value:byte(byte_index + 1))
end

local function has_char_boundary_at(value, byte_index)
  if byte_index <= 1 or byte_index > #value then
    return true
  end

  return not is_continuation_byte(value:byte(byte_index))
end

local function common_prefix_bytes(old, new)
  local max_len = math.min(#old, #new)
  local prefix = 0

  while prefix < max_len and old:byte(prefix + 1) == new:byte(prefix + 1) do
    prefix = prefix + 1
  end

  while prefix > 0 and (not has_char_boundary_after(old, prefix) or not has_char_boundary_after(new, prefix)) do
    prefix = prefix - 1
  end

  return prefix
end

local function common_suffix_bytes(old, new, prefix)
  local old_len = #old
  local new_len = #new
  local suffix = 0

  while old_len - suffix > prefix
    and new_len - suffix > prefix
    and old:byte(old_len - suffix) == new:byte(new_len - suffix)
  do
    suffix = suffix + 1
  end

  while suffix > 0 do
    local old_start = old_len - suffix + 1
    local new_start = new_len - suffix + 1

    if has_char_boundary_at(old, old_start) and has_char_boundary_at(new, new_start) then
      break
    end

    suffix = suffix - 1
  end

  return suffix
end

local function measure_change(old, new)
  if old == new then
    return 0, 0
  end

  local prefix = common_prefix_bytes(old, new)
  local suffix = common_suffix_bytes(old, new, prefix)
  local old_changed = old:sub(prefix + 1, #old - suffix)
  local new_changed = new:sub(prefix + 1, #new - suffix)

  return char_count(new_changed), char_count(old_changed)
end

local function snapshot(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, true)
  if not ok then
    return nil
  end

  return table.concat(lines, "\n")
end

local function apply_change(added, deleted)
  if added == 0 and deleted == 0 then
    return
  end

  state.added = state.added + added
  state.deleted = state.deleted + deleted
  state.dirty = true

  vim.schedule(function()
    vim.cmd.redrawstatus()
  end)
end

local function save_now()
  if not state.config or not state.config.persist or not state.dirty then
    return
  end

  local path = data_path()
  local payload = json_encode({
    added = state.added,
    deleted = state.deleted,
  })

  local ok = pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile({ payload }, path)
  end)

  if ok then
    state.dirty = false
  end
end

local function schedule_save()
  if not state.config or not state.config.persist or state.save_pending then
    return
  end

  state.save_pending = true

  vim.defer_fn(function()
    state.save_pending = false
    save_now()
  end, state.config.save_delay_ms)
end

local function update_snapshot(bufnr)
  local previous = state.snapshots[bufnr]
  local current = snapshot(bufnr)

  if not current then
    state.snapshots[bufnr] = nil
    return
  end

  if previous then
    local added, deleted = measure_change(previous, current)
    apply_change(added, deleted)
    schedule_save()
  end

  state.snapshots[bufnr] = current
end

local function load_stats()
  local path = data_path()

  if state.loaded and state.loaded_path == path then
    return
  end

  if not state.config.persist then
    state.loaded = true
    state.loaded_path = path
    return
  end

  if vim.fn.filereadable(path) ~= 1 then
    state.loaded = true
    state.loaded_path = path
    return
  end

  local ok, parsed = pcall(function()
    return json_decode(table.concat(vim.fn.readfile(path), "\n"))
  end)

  if ok and type(parsed) == "table" then
    state.added = tonumber(parsed.added) or 0
    state.deleted = tonumber(parsed.deleted) or 0
  end

  state.loaded = true
  state.loaded_path = path
end

local function ensure_setup()
  if state.config then
    return
  end

  M.setup({ auto_enable = false })
end

function M.setup(opts)
  opts = opts or {}
  state.config = vim.tbl_deep_extend("force", defaults, opts)

  if opts.data_path == nil then
    state.config.data_path = nil
  end

  load_stats()

  if state.config.auto_enable then
    M.enable()
  end

  return M
end

function M.enable()
  ensure_setup()

  if state.enabled then
    return
  end

  state.enabled = true
  state.augroup = vim.api.nvim_create_augroup("loc_nvim_tracker", { clear = true })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = state.augroup,
    callback = function(args)
      state.snapshots[args.buf] = snapshot(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = state.augroup,
    callback = function(args)
      update_snapshot(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("InsertLeave", {
    group = state.augroup,
    callback = function(args)
      update_snapshot(args.buf)
      state.snapshots[args.buf] = nil
      save_now()
    end,
  })
end

function M.disable()
  if not state.enabled then
    return
  end

  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end

  state.enabled = false
  state.augroup = nil
  state.snapshots = {}
  save_now()
end

function M.reset()
  ensure_setup()

  state.added = 0
  state.deleted = 0
  state.dirty = true
  save_now()
  vim.cmd.redrawstatus()
end

function M.stats()
  ensure_setup()

  return {
    added = state.added,
    deleted = state.deleted,
    net = state.added - state.deleted,
  }
end

function M.statusline()
  local stats = M.stats()
  local prefix = state.config.statusline_prefix

  return string.format("%s %+d", prefix, stats.net)
end

function M.save()
  ensure_setup()
  save_now()
end

M._measure_change = measure_change

return M
