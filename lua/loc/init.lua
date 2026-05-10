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
  days = {},
  metrics_render = 0,
}

local metrics_color_stops = {
  { at = 0.00, color = "#f0b6c1" },
  { at = 0.35, color = "#eba1ae" },
  { at = 0.65, color = "#df617a" },
  { at = 1.00, color = "#b90f36" },
}

local metrics_zero_style = {
  bg = "#252628",
  value_fg = "#e5e39a",
  date_fg = "#8f9096",
}

local metrics_low_text_style = {
  value_fg = "#2b2529",
  date_fg = "#58565b",
}

local metrics_high_text_style = {
  value_fg = "#ffd6df",
  date_fg = "#f0aebb",
}

local weekday_names = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local chars_per_loc = 35
local metrics_cell_width = 7
local metrics_cell_height = 3
local metrics_column_gap = 2
local metrics_row_gap = 1

local function data_path()
  return (state.config and state.config.data_path)
    or table.concat({ vim.fn.stdpath("data"), "loc.nvim", "stats.json" }, "/")
end

local json_encode = (vim.json and vim.json.encode) or vim.fn.json_encode
local json_decode = (vim.json and vim.json.decode) or vim.fn.json_decode

local function today_key()
  return vim.fn.strftime("%Y-%m-%d")
end

local function day_stats(date)
  state.days[date] = state.days[date] or { added = 0, deleted = 0 }
  return state.days[date]
end

local function char_count(value)
  if value == "" then return 0 end
  local ok, count = pcall(vim.fn.strchars, value)
  return ok and count or #value
end

local function is_continuation_byte(byte)
  return byte and byte >= 0x80 and byte <= 0xbf
end

local function has_char_boundary_at(value, byte_index)
  return byte_index <= 1 or byte_index > #value or not is_continuation_byte(value:byte(byte_index))
end

local function has_char_boundary_after(value, byte_index)
  return has_char_boundary_at(value, byte_index + 1)
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

  local day = day_stats(today_key())

  day.added = day.added + added
  day.deleted = day.deleted + deleted
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
  local payload = json_encode(state.days)

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

local function clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

local function chars_to_loc(chars)
  return (chars < 0 and -1 or 1) * math.floor((math.abs(chars) / chars_per_loc) + 0.5)
end

local function hex_to_rgb(color)
  return {
    r = tonumber(color:sub(2, 3), 16),
    g = tonumber(color:sub(4, 5), 16),
    b = tonumber(color:sub(6, 7), 16),
  }
end

local function rgb_to_hex(rgb)
  return string.format("#%02x%02x%02x", rgb.r, rgb.g, rgb.b)
end

local function lerp_number(start, finish, t)
  return math.floor(start + ((finish - start) * t) + 0.5)
end

local function lerp_color(start, finish, t)
  local from = hex_to_rgb(start)
  local to = hex_to_rgb(finish)

  return rgb_to_hex({
    r = lerp_number(from.r, to.r, t),
    g = lerp_number(from.g, to.g, t),
    b = lerp_number(from.b, to.b, t),
  })
end

local function metrics_color(t)
  t = clamp(t or 0, 0, 1)

  for index = 1, #metrics_color_stops - 1 do
    local left = metrics_color_stops[index]
    local right = metrics_color_stops[index + 1]

    if t <= right.at then
      local span = right.at - left.at
      local local_t = span == 0 and 0 or (t - left.at) / span

      return lerp_color(left.color, right.color, local_t)
    end
  end

  return metrics_color_stops[#metrics_color_stops].color
end

local function metrics_tile_style(net, max_abs_net)
  local abs_net = math.abs(net or 0)

  if abs_net == 0 or max_abs_net == 0 then
    return vim.tbl_extend("force", {}, metrics_zero_style)
  end

  local t = clamp(abs_net / max_abs_net, 0, 1)
  local text_style = t >= 0.75 and metrics_high_text_style or metrics_low_text_style

  return {
    bg = metrics_color(t),
    value_fg = text_style.value_fg,
    date_fg = text_style.date_fg,
  }
end

local function highlight_color(name, key)
  local ok, highlight = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })

  if not ok or type(highlight) ~= "table" or type(highlight[key]) ~= "number" then
    return nil
  end

  return highlight[key]
end

local function resolve_metrics_background()
  return {
    bg = highlight_color("StatusLine", "bg") or highlight_color("Normal", "bg"),
    fg = highlight_color("StatusLine", "fg") or highlight_color("Normal", "fg"),
  }
end

local function metrics_dates(now)
  now = now or vim.fn.localtime()

  local dates = {}
  local today_weekday = tonumber(vim.fn.strftime("%w", now))
  local current_week_start = now - (today_weekday * 86400)
  local range_start = current_week_start - (21 * 86400)

  for offset = 0, 27 do
    local epoch = range_start + (offset * 86400)

    dates[#dates + 1] = {
      date = vim.fn.strftime("%Y-%m-%d", epoch),
      epoch = epoch,
      weekday = tonumber(vim.fn.strftime("%w", epoch)),
    }
  end

  return dates
end

local function metrics_display_date(epoch)
  return vim.fn.strftime("%m/%d", epoch)
end

local function stored_day_stats(date)
  local day = state.days[date]

  if type(day) ~= "table" then
    return { added = 0, deleted = 0, net = 0 }
  end

  local added = tonumber(day.added) or 0
  local deleted = tonumber(day.deleted) or 0

  return {
    added = added,
    deleted = deleted,
    net = added - deleted,
  }
end

local function display_day_stats(stats)
  local loc_added = chars_to_loc(stats.added)
  local loc_deleted = chars_to_loc(stats.deleted)
  local loc_net = chars_to_loc(stats.net)

  return loc_added, loc_deleted, loc_net
end

local function collect_metrics_entries(now)
  local dates = metrics_dates(now)
  local entries = {}
  local max_abs_net = 0
  local total_net = 0

  for index, item in ipairs(dates) do
    local stats = stored_day_stats(item.date)
    local loc_added, loc_deleted, loc_net = display_day_stats(stats)
    local loc_abs_net = math.abs(loc_net)
    local entry = {
      index = index,
      date = item.date,
      display_date = metrics_display_date(item.epoch),
      weekday = item.weekday,
      column = math.floor((index - 1) / 7) + 1,
      added = stats.added,
      deleted = stats.deleted,
      net = stats.net,
      abs_net = math.abs(stats.net),
      loc_added = loc_added,
      loc_deleted = loc_deleted,
      loc_net = loc_net,
      loc_abs_net = loc_abs_net,
    }

    max_abs_net = math.max(max_abs_net, loc_abs_net)
    total_net = total_net + loc_net
    entries[#entries + 1] = entry
  end

  return entries, entries[#entries].column, max_abs_net, total_net
end

local function max_display_width(lines)
  local width = 0

  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  return width
end

local function centered_text(value, width)
  local display_width = vim.fn.strdisplaywidth(value)
  if display_width >= width then return value end
  local left = math.floor((width - display_width) / 2)
  return string.rep(" ", left) .. value .. string.rep(" ", width - display_width - left)
end

local function clamped_metric_value(value)
  value = clamp(value, -9999, 9999)
  return (value > 0 and "+" or "") .. value
end

local function build_metrics_lines(column_count, total_net)
  local horizontal_padding = 4
  local vertical_padding = 1
  local lines = {
    "LOC metrics",
    "",
  }
  local cells = {}

  for week = 1, column_count do
    local row_lines = {}
    local row_cells = {}

    for _ = 1, metrics_cell_height do
      row_lines[#row_lines + 1] = ""
    end

    for weekday = 0, 6 do
      local start_col = #row_lines[1]

      for row = 1, metrics_cell_height do
        row_lines[row] = row_lines[row] .. string.rep(" ", metrics_cell_width)
      end

      row_cells[weekday] = {
        line = #lines,
        value_line = #lines + 1,
        date_line = #lines + 2,
        start_col = start_col,
        end_col = #row_lines[1],
      }

      if weekday < 6 then
        local gap = string.rep(" ", metrics_column_gap)

        for row = 1, metrics_cell_height do
          row_lines[row] = row_lines[row] .. gap
        end
      end
    end

    cells[week] = row_cells

    for _, line in ipairs(row_lines) do
      lines[#lines + 1] = line
    end

    if week < column_count then
      for _ = 1, metrics_row_gap do
        lines[#lines + 1] = ""
      end
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("4-week net: %+d", total_net)

  local padded_lines = {}

  for _ = 1, vertical_padding do
    padded_lines[#padded_lines + 1] = ""
  end

  for _, line in ipairs(lines) do
    padded_lines[#padded_lines + 1] = string.rep(" ", horizontal_padding) .. line .. string.rep(" ", horizontal_padding)
  end

  for _ = 1, vertical_padding do
    padded_lines[#padded_lines + 1] = ""
  end

  for _, row_cells in pairs(cells) do
    for _, cell in pairs(row_cells) do
      cell.line = cell.line + vertical_padding
      cell.value_line = cell.value_line + vertical_padding
      cell.date_line = cell.date_line + vertical_padding
      cell.start_col = cell.start_col + horizontal_padding
      cell.end_col = cell.end_col + horizontal_padding
    end
  end

  return padded_lines, cells
end

local function set_metrics_keymaps(bufnr, winid)
  local function close()
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end

  local opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", "q", close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)

  -- Disable scrolling and movement
  local nop = function() end
  local keys = {
    "<PageUp>", "<PageDown>", "<ScrollWheelUp>", "<ScrollWheelDown>",
    "<Up>", "<Down>", "<Left>", "<Right>", "k", "j", "h", "l",
    "<C-f>", "<C-b>", "<C-d>", "<C-u>", "gg", "G"
  }

  for _, key in ipairs(keys) do
    vim.keymap.set("n", key, nop, opts)
  end
end

local function open_metrics_window(lines)
  local width = max_display_width(lines)
  local height = #lines
  local columns = vim.o.columns
  local rows = vim.o.lines

  width = math.min(width, math.max(1, columns - 4))
  height = math.min(height, math.max(1, rows - 4))

  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "locmetrics"

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((rows - height) / 2) - 1),
    col = math.max(0, math.floor((columns - width) / 2)),
    style = "minimal",
  })

  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = false
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].scrolloff = 0
  vim.wo[winid].sidescrolloff = 0
  set_metrics_keymaps(bufnr, winid)

  return bufnr, winid
end

local function set_metrics_window_highlights(winid)
  local normal_group = "LocMetricsNormal" .. state.metrics_render
  vim.api.nvim_set_hl(0, normal_group, resolve_metrics_background())
  vim.wo[winid].winhl = "Normal:" .. normal_group .. ",NormalFloat:" .. normal_group
end

local function apply_metrics_highlights(bufnr, cells, entries, max_abs_net)
  local namespace = vim.api.nvim_create_namespace("loc_metrics")
  local title_group = "LocMetricsTitle" .. state.metrics_render

  vim.api.nvim_set_hl(0, title_group, { italic = true })
  vim.api.nvim_buf_add_highlight(bufnr, namespace, title_group, 1, 4, 15)

  for _, entry in ipairs(entries) do
    local style = metrics_tile_style(entry.loc_net, max_abs_net)
    local group = string.format("LocMetricsCell%d_%02d", state.metrics_render, entry.index)
    local date_group = string.format("LocMetricsDate%d_%02d", state.metrics_render, entry.index)
    local cell = cells[entry.column][entry.weekday]
    local date = centered_text(entry.display_date, metrics_cell_width)

    vim.api.nvim_set_hl(0, group, { bg = style.bg, fg = style.value_fg })
    vim.api.nvim_set_hl(0, date_group, { bg = style.bg, fg = style.date_fg, italic = true })

    if entry.loc_net == 0 then
      vim.api.nvim_buf_set_text(bufnr, cell.value_line, cell.start_col, cell.value_line, cell.end_col, { date })
    else
      local value = centered_text(clamped_metric_value(entry.loc_net), metrics_cell_width)

      vim.api.nvim_buf_set_text(bufnr, cell.value_line, cell.start_col, cell.value_line, cell.end_col, { value })
      vim.api.nvim_buf_set_text(bufnr, cell.date_line, cell.start_col, cell.date_line, cell.end_col, { date })
    end

    for row = 0, metrics_cell_height - 1 do
      vim.api.nvim_buf_add_highlight(bufnr, namespace, group, cell.line + row, cell.start_col, cell.end_col)
    end

    local date_line = entry.loc_net == 0 and cell.value_line or cell.date_line

    vim.api.nvim_buf_add_highlight(bufnr, namespace, date_group, date_line, cell.start_col, cell.end_col)
  end
end

local function load_stats()
  local path = data_path()

  if state.loaded and state.loaded_path == path then
    return
  end

  if not state.config.persist then
    state.days = {}
    state.loaded = true
    state.loaded_path = path
    return
  end

  if vim.fn.filereadable(path) ~= 1 then
    state.days = {}
    state.loaded = true
    state.loaded_path = path
    return
  end

  local ok, parsed = pcall(function()
    return json_decode(table.concat(vim.fn.readfile(path), "\n"))
  end)

  state.days = {}
  state.dirty = false

  if ok and type(parsed) == "table" then
    for date, stats in pairs(parsed) do
      if type(date) == "string" and type(stats) == "table" then
        state.days[date] = {
          added = tonumber(stats.added) or 0,
          deleted = tonumber(stats.deleted) or 0,
        }
      end
    end
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

  local day = day_stats(today_key())

  day.added = 0
  day.deleted = 0
  state.dirty = true
  save_now()
  vim.cmd.redrawstatus()
end

function M.stats()
  ensure_setup()

  local day = day_stats(today_key())

  return {
    added = day.added,
    deleted = day.deleted,
    net = day.added - day.deleted,
  }
end

function M.display_stats()
  local stats = M.stats()
  local added, deleted, net = display_day_stats(stats)

  return {
    added = added,
    deleted = deleted,
    net = net,
  }
end

function M.statusline()
  local stats = M.display_stats()
  local prefix = state.config.statusline_prefix

  return string.format("%s %+d", prefix, stats.net)
end

function M.metrics()
  ensure_setup()

  local entries, column_count, max_abs_net, total_net = collect_metrics_entries()
  local lines, cells = build_metrics_lines(column_count, total_net)

  local bufnr, winid = open_metrics_window(lines)

  state.metrics_render = state.metrics_render + 1
  set_metrics_window_highlights(winid)
  vim.bo[bufnr].modifiable = true
  apply_metrics_highlights(bufnr, cells, entries, max_abs_net)
  vim.bo[bufnr].modifiable = false

  return {
    bufnr = bufnr,
    winid = winid,
    entries = entries,
    total_net = total_net,
    max_abs_net = max_abs_net,
  }
end

function M.save()
  ensure_setup()
  save_now()
end

M._measure_change = measure_change
M._metrics_color = metrics_color
M._metrics_dates = metrics_dates
M._metrics_entries = collect_metrics_entries
M._metrics_background = resolve_metrics_background
M._metrics_centered_text = centered_text
M._metrics_value = clamped_metric_value
M._metrics_tile_style = metrics_tile_style
M._metrics_display_date = metrics_display_date
M._chars_to_loc = chars_to_loc

return M
