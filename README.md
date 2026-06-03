# loc.nvim

A tiny Neovim plugin that tracks characters added and deleted while you are in
insert mode, then displays estimated lines of code by dividing characters by 35.

It keeps daily totals:

- `added`: characters inserted
- `deleted`: characters removed
- `net`: `added - deleted`

The statusline text shows today's `net`, for example:

```text
LOC +123
```
## Screens

<img width="694" height="490" alt="image" src="https://github.com/user-attachments/assets/38fad8e6-5480-4f6b-9f0d-066519e3551e" />

## Install

With `lazy.nvim`:

```lua
{
  "your-name/loc.nvim",
  config = function()
    require("loc").setup()
  end,
}
```

## Statusline

`loc.nvim` does not overwrite your statusline. Add the exposed function wherever
you want it.

Built-in statusline:

```lua
vim.o.statusline = vim.o.statusline .. " %{v:lua.require'loc'.statusline()}"
```

With `lualine.nvim`:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      function()
        return require("loc").statusline()
      end,
    },
  },
})
```

## Commands

The plugin defines these commands when it is on your runtimepath:

- `:LocEnable` starts tracking.
- `:LocDisable` stops tracking.
- `:LocReset` clears today's counters.
- `:LocStats` prints today's counters.
- `:LocMetrics` opens a floating 4-week net LOC heatmap.

Calling `require("loc").setup()` enables tracking by default. Use this if you
want to configure the plugin but start it manually:

```lua
require("loc").setup({ auto_enable = false })
```

## Configuration

Defaults:

```lua
require("loc").setup({
  auto_enable = true,
  data_path = nil,
  flush_interval_ms = 10000,
  statusline_prefix = "LOC",
})
```

When `data_path` is `nil`, stats are stored at:

```text
stdpath("data")/loc.nvim/stats.json
```

Stats are stored by local date:

```json
{
  "2026-04-30": {
    "added": 123,
    "deleted": 45
  }
}
```

Local edits are applied immediately in the UI, then flushed into `stats.json` every `flush_interval_ms`.

## API

```lua
require("loc").enable()
require("loc").disable()
require("loc").reset()
require("loc").save()
require("loc").statusline()
require("loc").stats()
require("loc").metrics()
```

`save()` flushes this process's pending deltas immediately.

`stats()` returns today's counters:

```lua
{
  added = 123,
  deleted = 45,
  net = 78,
}
```

## Test

From the repository root:

```sh
nvim --headless -u NONE -i NONE -l test/loc_spec.lua
```
