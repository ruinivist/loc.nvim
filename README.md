# loc.nvim

> Entirely GPT 5.5 generated

A tiny Neovim plugin that tracks characters added and deleted while you are in
insert mode.

It keeps global lifetime totals:

- `added`: characters inserted
- `deleted`: characters removed
- `net`: `added - deleted`
- `abs`: `added + deleted`

The statusline text shows `net/abs`, for example:

```text
LOC +123/456
```

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

For a local checkout:

```lua
{
  dir = "/Users/zero/main/loc.nvim",
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
- `:LocReset` clears the counters.
- `:LocStats` prints the current counters.

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
  persist = true,
  data_path = nil,
  save_delay_ms = 1000,
  statusline_prefix = "LOC",
})
```

When `data_path` is `nil`, stats are stored at:

```text
stdpath("data")/loc.nvim/stats.json
```

## API

```lua
require("loc").enable()
require("loc").disable()
require("loc").reset()
require("loc").save()
require("loc").statusline()
require("loc").stats()
```

`stats()` returns:

```lua
{
  added = 123,
  deleted = 45,
  net = 78,
  abs = 168,
}
```

## Test

From the repository root:

```sh
nvim --headless -u NONE -i NONE -l test/loc_spec.lua
```
