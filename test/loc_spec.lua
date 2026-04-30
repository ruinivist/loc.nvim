vim.opt.runtimepath:prepend(vim.fn.getcwd())

local loc = require("loc")

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", message, vim.inspect(expected), vim.inspect(actual)))
  end
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

local tmp = vim.fn.tempname()
loc.setup({ auto_enable = false, data_path = tmp, save_delay_ms = 1 })
loc.reset()

local stats = loc.stats()
assert_equal(stats.added, 0, "reset added")
assert_equal(stats.deleted, 0, "reset deleted")
assert_equal(loc.statusline(), "LOC +0/0", "statusline")

print("loc.nvim tests passed")
