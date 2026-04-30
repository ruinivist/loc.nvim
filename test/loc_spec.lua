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

local today = vim.fn.strftime("%Y-%m-%d")
local old_day = "2000-01-01"

local daily_path = vim.fn.tempname()
write_json(daily_path, {
  [today] = { added = 7, deleted = 2 },
  [old_day] = { added = 4, deleted = 1 },
})

loc.setup({ auto_enable = false, data_path = daily_path, save_delay_ms = 1 })

local loaded_stats = loc.stats()
assert_equal(loaded_stats.added, 7, "loaded daily added")
assert_equal(loaded_stats.deleted, 2, "loaded daily deleted")
assert_equal(loaded_stats.net, 5, "loaded daily net")
assert_equal(loc.statusline(), "LOC +5", "daily statusline")

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
loc.setup({ auto_enable = false, data_path = change_path, save_delay_ms = 1 })
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

loc.save()
loc.disable()
vim.wait(20)
vim.api.nvim_buf_delete(bufnr, { force = true })

local changed = read_json(change_path)
assert_equal(changed[today].added, 2, "tracked edit saved today added")
assert_equal(changed[today].deleted, 0, "tracked edit saved today deleted")

print("loc.nvim tests passed")
