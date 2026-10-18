# damnit.nvim

The [`dam`](https://github.com/webdavis/damnit) task store from inside Neovim.

`dam` stages and commits tasks like git and pushes them to a remote. This plugin drives the `dam`
command line and nothing else. Every `dam` call runs in the background, so the editor never waits
on one.

## Requirements

- Neovim 0.12.5.
- `dam` on your `PATH`, `>=0.2.0 <0.3.0`. Any other version is refused.
- [fzf-lua](https://github.com/ibhagwan/fzf-lua), optional. Without it the search uses
  `vim.ui.select`.

`:checkhealth damnit` reports what it found.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  "webdavis/damnit.nvim",
  cmd = "Dam",
  opts = {
    views = { today = "due:today | overdue" },
  },
  keys = {
    { "<leader>Ts", "<Cmd>Dam<CR>", desc = "dam: the staging window" },
    { "<leader>Tt", "<Cmd>Dam list<CR>", desc = "dam: every open task" },
    { "<leader>Tc", ":Dam capture<CR>", mode = { "n", "x" }, desc = "dam: capture a task" },
  },
}
```

`setup` is optional. A later call merges over the earlier one.

## Commands

| Command | What it does |
| --- | --- |
| `:Dam` | Open the staging window. |
| `:Dam list [<view>]` | List one view, or every open object. |
| `:Dam task <oid>` | Open one object as an editable buffer. |
| `:Dam pick [<view>]` | Search a view and open what you pick. |
| `:Dam done` | List what is completed, newest first. |
| `:Dam toggle` | Open or close the sidebar. |
| `:Dam capture` | Make a task from the line or selection in front of you. |
| `:Dam cancel` | Cancel the running `dam` call. |
| `:Dam messages` | Show the last 200 messages in full. |

Each message is one line starting `damnit.nvim:`, cut to fit; `:Dam messages` keeps the full text.

## The staging window

`:Dam` shows a header naming the store and each remote, a legend of its main keys, then Conflicts,
Working, Staged, Unpushed and Notices, each only when it holds something.

| Key | What it does |
| --- | --- |
| `-` | Stage or unstage this object. On a heading, the whole section. Takes a visual range. |
| `s` `u` | Stage, or unstage, this object. Takes a visual range. |
| `U` | Unstage everything. |
| `cc` | Commit what is staged, in a message buffer; `:w` makes the commit. |
| `X` | Discard this working change, after a confirm. |
| `=` | Show or hide which fields this change touches. |
| `<CR>` | Open what the cursor is on. |
| `R` | Re-read the status. |
| `P` `p` | Push, pull. |
| `co` `ct` | Resolve this conflict with ours, with theirs. |
| `<C-c>` | Cancel the running operation. |
| `gu` `gs` `gp` `gn` `gc` | Jump to Working, Staged, Unpushed, Notices, Conflicts. |
| `q` `gq` | Close the window. |
| `g?` | Show the keys of this buffer. |

`X` puts an update or a delete back to its last commit, and removes a create.

## The task buffer

`:Dam task <oid>`, or `<CR>` on an object, opens it as a `key: value` header between `---` fences,
with the body below.

```
---
subject: pay the rent
path: home/
done: false
priority: 1
due: 2026-10-18
deadline:
labels: bills
depends:
recurrence:
# reminders:
# priority: 1 is highest
---
Bank transfer only.
```

Writing it sends only the fields you changed, and stops at the first one `dam` refuses. A refusal is
shown on its field's line. `#` lines are read only. Changing `path` moves the object there. `done`
takes only `false`; complete an object with `x` in a list.

## Lists and views

`:Dam list` shows every open object as a tree of paths. `:Dam list <view>` runs one view: a name
from the `views` option, or one of `dam`'s saved filters. A view's value is a `dam ls` query. Each
line is the subject, then the due date, priority, labels, `⌖` if captured from code, and the path.

| Key | What it does |
| --- | --- |
| `<CR>` | Open this object. |
| `x` | Complete this object. If it waits on an open task, offers to complete it anyway. |
| `X` | Reopen this object. |
| `u` | Reopen this object, in the completed history. |
| `dd` | Remove this object, after a confirm. |
| `p` | Cycle its priority. |
| `s` | Set its due date. |
| `l` | Toggle a label on it. |
| `m` | Move it into another path. |
| `>` `<` | Move it under the object above, or out from under its parent. |
| `a` | Add an object where the cursor is. |
| `za` | Fold or unfold what is nested here. |
| `gd` | Jump to the code this task was captured from. |
| `S` | Hand it to the agent pane. |
| `R` | Re-read this view. |
| `g?` | Show the keys of this buffer. |

`:Dam pick` searches the same objects; in fzf-lua `ctrl-x` completes the pick.

`:Dam capture` makes a task in `inbox/`. A visual selection becomes its subject, without comment
marks or a leading `TODO(author):`; in normal mode it asks. The body names the file and line, which
`gd` jumps back to.

`S` asks for a note, then pastes a brief of the object into the [herdr](https://herdr.dev) agent
pane without submitting it. Outside herdr the brief goes to the clipboard.

## The sidebar, statusline and reminders

`:Dam toggle` opens the `sidebar.view` list in a split of fixed width.

`require("damnit").status()` returns a statusline string such as `2 due, 1 overdue`, the running
call as `dam: push todoist 3.2s`, or `dam !` when the last read failed:

```lua
vim.o.statusline = "%{%v:lua.require('damnit').status()%}"
```

With `reminders = true`, a task with a time of day raises one notification when that time passes.

## Options

| Option | Default | What it does |
| --- | --- | --- |
| `views` | `{}` | A view name to the `dam` query it runs. |
| `picker` | `"auto"` | `auto`, `fzf-lua` or `select`. |
| `sidebar.side` | `"left"` | `left` or `right`. |
| `sidebar.width` | `40` | Columns of the sidebar. |
| `sidebar.view` | `"today"` | The view the sidebar shows. |
| `refresh_interval` | `60` | Seconds between the reads behind `status()`. |
| `reminders` | `false` | Notify when a timed task comes due. |
| `store` | `nil` | Passed as `--store`. |
| `config` | `nil` | Passed as `--config`. |
| `timeout` | `120` | Seconds one `dam` call may run. |
| `window.float` | `false` | Open the staging window as a float. |

## Lua API

| Function | What it does |
| --- | --- |
| `require("damnit").setup(opts)` | Merge options. |
| `require("damnit").open_status()` | Open the staging window. |
| `require("damnit").open(name?)` | Open one view as a list. |
| `require("damnit").completed()` | Open the completed history. |
| `require("damnit").pick(name?)` | Search one view. |
| `require("damnit").toggle()` | Toggle the sidebar. |
| `require("damnit").status()` | The statusline string. |

## Tests

```bash
nvim --headless --clean -l tests/run.lua
stylua --check . && luacheck .
```

## License

MIT. See [LICENSE](LICENSE).
