vim.opt.runtimepath:prepend(vim.fn.getcwd())

local loc = require("loc")

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, vim.inspect(expected), vim.inspect(actual)))
  end
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

local function read_json(path)
  return json_decode(table.concat(vim.fn.readfile(path), "\n"))
end

local function write_json(path, value)
  vim.fn.writefile({ json_encode(value) }, path)
end

local function assert_change(old, new, expected_added, expected_deleted)
  local added, deleted = loc._measure_change(old, new)

  assert_equal(added, expected_added, string.format("added for %q -> %q", old, new))
  assert_equal(deleted, expected_deleted, string.format("deleted for %q -> %q", old, new))
end

assert_change("", "abc", 3, 0)
assert_change("abc", "ab", 0, 1)
assert_change("abc", "axc", 1, 1)
assert_change("hello", "hello world", 6, 0)
assert_change("héllo", "hallo", 1, 1)
assert_change("one\ntwo", "one\nthree", 4, 2)

assert_equal(loc._chars_to_loc(0), 0, "chars to loc zero")
assert_equal(loc._chars_to_loc(17), 0, "chars to loc below half")
assert_equal(loc._chars_to_loc(18), 1, "chars to loc rounds half up")
assert_equal(loc._chars_to_loc(35), 1, "chars to loc one line")
assert_equal(loc._chars_to_loc(52), 1, "chars to loc below one and a half")
assert_equal(loc._chars_to_loc(53), 2, "chars to loc above one and a half")
assert_equal(loc._chars_to_loc(-70), -2, "chars to loc negative")

local today = vim.fn.strftime("%Y-%m-%d")
local old_day = "2000-01-01"

local daily_path = vim.fn.tempname()
write_json(daily_path, {
  [today] = { added = 7, deleted = 2 },
  [old_day] = { added = 4, deleted = 1 },
})

loc.setup({ auto_enable = false, data_path = daily_path, flush_interval_ms = 10000 })

local loaded_stats = loc.stats()
assert_equal(loaded_stats.added, 7, "loaded daily added")
assert_equal(loaded_stats.deleted, 2, "loaded daily deleted")
assert_equal(loaded_stats.net, 5, "loaded daily net")
assert_equal(loc.statusline(), "LOC +0", "daily statusline uses estimated loc")

loc.reset()

local stats = loc.stats()
assert_equal(stats.added, 0, "reset added")
assert_equal(stats.deleted, 0, "reset deleted")
assert_equal(loc.statusline(), "LOC +0", "statusline")

local daily = read_json(daily_path)
assert_equal(daily[today].added, 0, "reset today added on disk")
assert_equal(daily[today].deleted, 0, "reset today deleted on disk")
assert_equal(daily[old_day].added, 4, "reset preserves old day added")
assert_equal(daily[old_day].deleted, 1, "reset preserves old day deleted")

local change_path = vim.fn.tempname()
loc.setup({ auto_enable = false, data_path = change_path, flush_interval_ms = 10000 })
loc.enable()

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { "a" })
vim.api.nvim_exec_autocmds("InsertEnter", { buffer = bufnr })
vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { "abc" })
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })

local changed_stats = loc.stats()
assert_equal(changed_stats.added, 2, "tracked edit added")
assert_equal(changed_stats.deleted, 0, "tracked edit deleted")
assert_equal(loc.display_stats().added, 0, "tracked edit display added")

loc.save()
loc.disable()
vim.wait(20)
vim.api.nvim_buf_delete(bufnr, { force = true })

local changed = read_json(change_path)
assert_equal(changed[today].added, 2, "tracked edit saved today added")
assert_equal(changed[today].deleted, 0, "tracked edit saved today deleted")

local metrics_epoch = vim.fn.strptime("%Y-%m-%d", "2026-05-10")
local metrics_dates = loc._metrics_dates(metrics_epoch)

assert_equal(#metrics_dates, 28, "metrics date count")
assert_equal(metrics_dates[1].date, "2026-04-19", "metrics first date")
assert_equal(metrics_dates[28].date, "2026-05-16", "metrics last date")
assert_equal(loc._metrics_color(0), "#f0b6c1", "metrics active color start")
assert_equal(loc._metrics_color(1), "#b90f36", "metrics active color end")

local zero_style = loc._metrics_tile_style(0, 9999)
assert_equal(zero_style.bg, "#252628", "metrics zero tile background")
assert_equal(zero_style.value_fg, "#e5e39a", "metrics zero value foreground")
assert_equal(zero_style.date_fg, "#8f9096", "metrics zero date foreground")

local low_style = loc._metrics_tile_style(2000, 9999)
assert_equal(low_style.bg, "#edaab6", "metrics low tile background")
assert_equal(low_style.value_fg, "#2b2529", "metrics low value foreground")
assert_equal(low_style.date_fg, "#58565b", "metrics low date foreground")

local high_style = loc._metrics_tile_style(9999, 9999)
assert_equal(high_style.bg, "#b90f36", "metrics high tile background")
assert_equal(high_style.value_fg, "#ffd6df", "metrics high value foreground")
assert_equal(high_style.date_fg, "#f0aebb", "metrics high date foreground")

assert_equal(loc._metrics_value(12000), "+9999", "metrics positive value clamps")
assert_equal(loc._metrics_value(-12000), "-9999", "metrics negative value clamps")
assert_equal(loc._metrics_value(0), "0", "metrics zero value")
assert_equal(loc._metrics_centered_text("+7", 7), "  +7   ", "metrics centered value")
assert_equal(loc._metrics_display_date(metrics_dates[1].epoch), "04/19", "metrics display date")

vim.api.nvim_set_hl(0, "Normal", { fg = 0x112233, bg = 0x445566 })
vim.api.nvim_set_hl(0, "NormalFloat", { fg = 0xaabbcc, bg = 0xddeeff })
vim.api.nvim_set_hl(0, "StatusLine", { fg = 0x778899, bg = 0x0a0b0c })

local metrics_background = loc._metrics_background()
assert_equal(metrics_background.fg, 0x778899, "metrics background fg from StatusLine")
assert_equal(metrics_background.bg, 0x0a0b0c, "metrics background bg from StatusLine")

vim.api.nvim_set_hl(0, "Normal", { fg = 0x010203, bg = 0x040506 })
vim.api.nvim_set_hl(0, "StatusLine", {})

metrics_background = loc._metrics_background()
assert_equal(metrics_background.fg, 0x010203, "metrics background fg falls back to Normal")
assert_equal(metrics_background.bg, 0x040506, "metrics background bg falls back to Normal")

local metrics_path = vim.fn.tempname()
write_json(metrics_path, {
  [metrics_dates[1].date] = { added = 245, deleted = 0 },
  [metrics_dates[10].date] = { added = 0, deleted = 105 },
  ["2026-05-10"] = { added = 350, deleted = 0 },
})

loc.setup({ auto_enable = false, data_path = metrics_path, flush_interval_ms = 10000 })

local entries, column_count, max_abs_net, total_net = loc._metrics_entries(metrics_epoch)

assert_equal(#entries, 28, "metrics entry count")
assert_equal(column_count, 4, "metrics column count")
assert_equal(entries[1].net, 245, "metrics first entry raw net")
assert_equal(entries[1].loc_net, 7, "metrics first entry loc net")
assert_equal(entries[1].display_date, "04/19", "metrics first entry display date")
assert_equal(entries[2].net, 0, "metrics missing entry net")
assert_equal(entries[10].net, -105, "metrics negative raw entry net")
assert_equal(entries[10].loc_net, -3, "metrics negative loc entry net")
assert_equal(entries[22].date, "2026-05-10", "metrics current week starts with today")
assert_equal(entries[22].column, 4, "metrics today is in current week column")
assert_equal(entries[22].weekday, 0, "metrics today is Sunday row")
assert_equal(entries[28].date, "2026-05-16", "metrics includes future week end")
assert_equal(entries[28].loc_net, 0, "metrics future date loc net is zero")
assert_equal(max_abs_net, 10, "metrics max abs net")
assert_equal(total_net, 14, "metrics total net")

local render_path = vim.fn.tempname()
local render_dates = loc._metrics_dates()
write_json(render_path, {
  [render_dates[1].date] = { added = 245, deleted = 0 },
  [render_dates[10].date] = { added = 0, deleted = 105 },
  [today] = { added = 350, deleted = 0 },
})

loc.setup({ auto_enable = false, data_path = render_path, flush_interval_ms = 10000 })

local render = loc.metrics()
assert_equal(vim.api.nvim_win_is_valid(render.winid), true, "metrics window is valid")
assert_equal(vim.api.nvim_buf_is_valid(render.bufnr), true, "metrics buffer is valid")

local metrics_lines = vim.api.nvim_buf_get_lines(render.bufnr, 0, -1, false)
local rendered = table.concat(metrics_lines, "\n")

assert_equal(metrics_lines[2]:match("LOC metrics") ~= nil, true, "metrics title")
assert_equal(metrics_lines[#metrics_lines - 1]:match("4%-week net: %+14") ~= nil, true, "metrics summary")
assert_equal(#metrics_lines, 21, "metrics renders transposed three-line week rows with row gaps and outer padding")
assert_equal(rendered:match("%+7") ~= nil, true, "metrics renders net value")
assert_equal(rendered:match(loc._metrics_display_date(render_dates[1].epoch)) ~= nil, true, "metrics renders date label")
assert_equal(rendered:match(loc._metrics_display_date(render_dates[2].epoch)) ~= nil, true, "metrics renders zero tile date label")
assert_equal(rendered:match(loc._metrics_display_date(render_dates[28].epoch)) ~= nil, true, "metrics renders future date label")
assert_equal(rendered:match("Sun") == nil, true, "metrics omits weekday labels")
assert_equal(vim.wo[render.winid].winhl:match("LocMetricsNormal") ~= nil, true, "metrics window uses custom normal highlight")
assert_equal(vim.wo[render.winid].winhl:match("FloatBorder") == nil, true, "metrics window does not set a border highlight")

vim.api.nvim_win_close(render.winid, true)

print("loc.nvim tests passed")
