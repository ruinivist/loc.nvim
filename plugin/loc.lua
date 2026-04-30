if vim.g.loaded_loc_nvim == 1 then
  return
end

vim.g.loaded_loc_nvim = 1

vim.api.nvim_create_user_command("LocEnable", function()
  require("loc").enable()
end, { desc = "Enable loc.nvim insert-mode character tracking" })

vim.api.nvim_create_user_command("LocDisable", function()
  require("loc").disable()
end, { desc = "Disable loc.nvim insert-mode character tracking" })

vim.api.nvim_create_user_command("LocReset", function()
  require("loc").reset()
end, { desc = "Reset loc.nvim character counters" })

vim.api.nvim_create_user_command("LocStats", function()
  local stats = require("loc").stats()
  local message = string.format(
    "LOC added=%d deleted=%d net=%+d",
    stats.added,
    stats.deleted,
    stats.net
  )

  vim.notify(message, vim.log.levels.INFO)
end, { desc = "Show loc.nvim character counters" })
