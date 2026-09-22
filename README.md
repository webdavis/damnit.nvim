# damnit.nvim

The [`dam`](https://github.com/webdavis/damnit) task store from inside Neovim.

`dam` is a task and event store that is staged and committed like git: you change objects in a
working layer, stage what you meant, commit it, and push to a remote. It keeps the credentials for
whatever remote it speaks to, in its own config file.

This plugin is a client of the `dam` command line and nothing else. Its default surface is a
fugitive-style staging window: working changes, the stage, what is unpushed, notices and conflicts,
with a key for each thing you can do to a line. Every call it makes is non-blocking, so the editor
never stops while a push runs.

**It holds no credential.** There is no token option, no keychain option, no environment variable to
name, and nothing in this repository ever sees one. `dam` resolves its own.

## Requirements

- Neovim 0.12.5. It is developed and tested there, and needs `vim.system`, `vim.uv`, extmarks and
  `vim.health`.
- `dam` on your `PATH`, in the range `>=0.2.0 <0.3.0`. Older or newer and the plugin says so and
  refuses rather than guessing at a document shape.
- No token. See above.
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) is optional. Without it the search falls back to
  `vim.ui.select`.

Run `:checkhealth damnit` to see what it found.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  "webdavis/damnit.nvim",
  cmd = "Dam",
  opts = {
    views = {
      today = "due:today | overdue",
      upcoming = "due:this-week | due:next-week",
      dotfiles = "path:dotfiles/ & !done",
    },
  },
  keys = {
    { "<leader>Ts", "<Cmd>Dam<CR>", desc = "dam: the staging window" },
    { "<leader>Tt", "<Cmd>Dam list<CR>", desc = "dam: every open task" },
    { "<leader>Td", "<Cmd>Dam list today<CR>", desc = "dam: today" },
    { "<leader>Tb", "<Cmd>Dam toggle<CR>", desc = "dam: toggle the sidebar" },
    { "<leader>Tp", "<Cmd>Dam pick<CR>", desc = "dam: search the tasks" },
    { "<leader>Th", "<Cmd>Dam done<CR>", desc = "dam: the completed history" },
    { "<leader>Tc", "<Cmd>Dam capture<CR>", desc = "dam: capture a task from here" },
    { "<leader>Tc", ":Dam capture<CR>", mode = "x", desc = "dam: capture this selection" },
  },
}
```

`setup` is optional: every command works without it. Calling it is how you declare views and change
the options below.

## Commands

| Command | What it does |
| --- | --- |
| `:Dam` | The staging window. |
| `:Dam list [<view>]` | One named view as a list, or every open object. |
| `:Dam task <oid>` | One object as an editable buffer. |
| `:Dam pick [<view>]` | Fuzzy-search a view and act on what you picked. |
| `:Dam done` | The completed history, newest first. |
| `:Dam toggle` | Open or close the sidebar. |
| `:Dam capture` | Capture a task from the code in front of you. Takes a range. |
| `:Dam cancel` | Cancel the running operation. |

`:Dam` completes its subcommands, and after `list` or `pick` it completes your declared view names.
The command is declared at load rather than behind `setup`, so `nvim +"Dam task <oid>"` works in an
editor holding nothing else.

## The staging window

`:Dam` opens it. It draws a header, then one section per thing that has something in it: Conflicts,
Working, Staged, Unpushed, Notices. Each section is a fold. It re-reads `dam status --json` in full
after every action rather than patching its own model, so what you see is what dam last said.

| Key | What it does |
| --- | --- |
| `-` | Stage or unstage the object under the cursor. Takes a visual range. |
| `s` | Stage it. Takes a visual range. |
| `u` | Unstage it. Takes a visual range. |
| `U` | Unstage everything. |
| `cc` | Commit what is staged, in a message buffer. |
| `X` | Discard this working change. |
| `=` | Show or hide which fields this change touches. |
| `<CR>` | Open what the cursor is on. |
| `R` | Re-read the status. |
| `P` | Push. |
| `p` | Pull. |
| `co` | Settle this conflict with ours. |
| `ct` | Settle this conflict with theirs. |
| `<C-c>` | Cancel the running operation. |
| `gu` `gs` `gp` `gn` `gc` | Jump to Working, Staged, Unpushed, Notices, Conflicts. |
| `q` `gq` | Close the window. |
| `g?` | Show this table for the buffer you are in. |

`X` works on an uncommitted create only. On a change whose op is an update or a delete it says so
and does nothing, because throwing one of those away means restoring the committed state and this
key does not do that yet.

Every highlight group links to a standard group, so the window takes your colourscheme's colours and
this plugin writes none of its own.

## Non-blocking, and what that means here

Every `dam` call is spawned with a callback. Nothing in this plugin waits on one, with a single
exception: `:checkhealth damnit`, which runs because you asked for a report and has nothing to do
but wait. CI greps for both rules.

One call runs per store at a time, so the plugin is never a second writer against its own store and
a push and a pull cannot overlap. A second network call is refused rather than queued: a queued push
is a push nobody asked for, against a store that has moved since they asked, arriving minutes later
with no one watching.

While something runs, its label and elapsed time are written into the window's header and into the
statusline, and `<C-c>` or `:Dam cancel` stops it. Cancelling sends an interrupt first, so dam gets
to stop its helper and leave the store consistent, then escalates if it will not stop.

## The task buffer

`:Dam task <oid>`, or `<CR>` on a line that names an object, opens it as text: a header of
`key: value` lines between two `---` fences, and the body as markdown below them.

```
---
subject: pay the rent
path: home/
done: false
priority: 1
due: 2026-10-01
deadline:
labels: bills, monthly
depends:
recurrence: every month
# reminders:
# priority: 1 is highest
---
The landlord takes a bank transfer only.
```

Write the buffer and only what you changed is sent. Lines starting with `#` inside the header are
read only. The buffer stays modified until dam answers, so an edit that has not landed still reads
as unwritten and a refused one leaves your text where you can fix it.

**Priority 1 is the most urgent**, which is the reverse of Todoist's scale. The header says so on its
own read-only line.

Two fields behave unlike the rest. `path` moves the object with `dam mv`, which puts it inside the
path you name and keeps the object's own last segment, so changing that last segment is a rename and
is refused with an explanation. `done` takes `false` and sends `dam edit --undone`; complete an
object with `x` in a list, not by typing `true` here, because completing a recurring object rolls it
forward instead of setting a flag.

## Lists and named views

`:Dam list` shows every open object as a tree built from each object's `path`. `:Dam list <view>`
shows one view. A view name is looked up in your `views` option first and then handed to `dam`,
which resolves its own saved filters, so a name declared in `dam`'s config works in the editor, in a
terminal and in a herdr pane from one declaration.

A view's value is a dam query. The grammar, as `dam 0.2.0` reads it:

| Term | Matches |
| --- | --- |
| `done`, `overdue` | Completed; open and due before today. |
| `due:`, `deadline:`, `start:` | A date selector, below. |
| `path:work/` | Everything at or under that path. |
| `@bills`, `label:bills` | That label. |
| `p1`, `priority:1` | That priority, 1 being the most urgent. |
| `kind:task`, `kind:event` | One kind. |
| `subject:rent` | A subject holding that text. |
| `attached:<oid>` | The task attached to that event. |
| `transparency:busy`, `transparency:free` | An event's transparency. |
| `<category>:<value>` | A label in a category `dam`'s config declares. |

Date selectors are `today`, `tomorrow`, `yesterday`, `this-week`, `next-week`, `none`, a bare
`YYYY-MM-DD`, `before:YYYY-MM-DD` and `after:YYYY-MM-DD`.

Combine terms with `&`, `|` and `!`, and group with parentheses: `path:work/ & !done & (due:today |
overdue)`.

| Key | What it does |
| --- | --- |
| `<CR>` | Open this object as a buffer. |
| `R` | Re-read this view. |
| `za` | Fold or unfold what is nested here. |
| `gd` | Jump to the code this task was captured from. |
| `x` | Complete this object. |
| `X` | Reopen this object. |
| `dd` | Remove this object, after a confirm. |
| `p` | Cycle its priority. |
| `s` | Set its due date. |
| `l` | Toggle a label on it. |
| `m` | Move it into another path. |
| `a` | Add an object where the cursor is. |
| `>` `<` | Move it under the object above, or out from under its parent. |
| `S` | Hand it to the agent pane. |
| `g?` | Show this table. |

Completing a parent whose children or dependencies are still open is refused by `dam`, which names
the blockers. The plugin shows you that list and asks what to do with them rather than asking yes or
no.

## The completed history

`:Dam done` lists what is completed, newest first, flat rather than as a tree. `dam` holds the whole
history and answers it in one call, so there is nothing to page through.

`u` reopens the object under the cursor there. It is confined to this buffer on purpose: a plain
`dam ls` view holds completed objects too, and reopening one from there is `X`.

## Searching

`:Dam pick [<view>]` fuzzy-searches the objects of a view, in fzf-lua when it is installed and
`vim.ui.select` when it is not. With no name it searches the view the list buffer is showing, or
every open object. The prompt carries the view's name and its query, so a search that is looking
inside a filter says so.

## Capture from code

`:Dam capture` makes a task out of what is in front of you. In visual mode the selection becomes the
subject, taken by whole lines; in normal mode it asks. Either way the task's body gets one line
naming where it came from:

```
-- TODO(me): hold the width
```

captured from `lua/damnit/sidebar.lua` becomes a task whose body holds
`damnit.nvim lua/damnit/sidebar.lua:88`, and `gd` on that task in a list takes you back to the line.

The path is always relative to the repository root, and a file in no repository goes out as its own
name alone. A body reaches every device that pulls the store, so an absolute path would carry the
home directory of the machine that captured it.

Nothing else is set, so a capture lands in `inbox/`, which is where it belongs until you triage it.

## Sending an object to the agent

`S` in a list hands the object under the cursor to the agent pane as a plain-text brief. Inside
[herdr](https://github.com/webdavis/herdr) it goes into the agent pane's input as one bracketed
paste and is never submitted, so you read it, add to it and press return yourself. Outside herdr, or
whenever herdr will not take it, the same brief goes to the clipboard and the notification says so.

`dam` has no comments, so a hand-off leaves no record in the store. Every notification says that.

## The sidebar

`:Dam toggle` opens one view as a fixed-width split beside your work, and closes the one this
tabpage has. The window is the state: `:q` closes it and there is no separate record, so the plugin
and Neovim cannot disagree about whether it is open. Its width is held with `winfixwidth`, and
`winfixbuf` keeps another buffer out of it.

Configure the side, the width and which view it opens under `sidebar` in the options.

## The statusline

`require("damnit").status()` returns a string for a statusline component:

```lua
vim.o.statusline = "%{%v:lua.require('damnit').status()%}"
```

It draws nothing until the first read lands and nothing again whenever nothing is due, which is the
right answer for no news. Otherwise it is `2 due, 1 overdue`. While a foreground `dam` call is running
it is that instead, with its elapsed time: `dam: push todoist 3.2s`. A background read leaves the count
in place. A read that failed reads `dam !`, because a count left standing after the store stopped
answering is worse than no count.

Asking for the string is what starts the reader. It runs `dam ls '!done & (due:today | overdue)'
--no-pull` every `refresh_interval` seconds, skips a turn while another call holds the store, and
stops on exit. `--no-pull` is what lets it promise to reach no remote.

## Due reminders

With `reminders = true`, a task with a time of day raises one notification when that time passes. A
whole-day task never does: it has no moment to come due at.

The first read of a session only records what is already overdue, so opening the editor in the
evening does not replay the morning. An instant is announced once, keyed by the object and the time,
so the next iteration of a recurring task and a task you moved to a new time are both announced
again.

Reminders ride on the same reader as the statusline. Turning them on is what starts it if your
statusline does not.

## Health

`:checkhealth damnit` reports, in the order things can fail:

- `dam`'s version against the supported range, or the install line when it is not there.
- Whether the store answers, and how many objects it holds.
- Which store and config the plugin passes, and where each came from.
- One line per configured remote and the helper it speaks through.
- `dam`'s own saved filters, which `:Dam list` takes by name.
- A warning with the count when the store holds a conflict.
- Every view you declared, run against `dam`, with an error naming any query it refuses and carrying
  dam's own words.

It reports nothing about any credential, because it never sees one.

## Options

Pass these to `setup`, or as `opts` in a lazy.nvim spec.

| Option | Default | What it does |
| --- | --- | --- |
| `views` | `{}` | A view name to the dam query it runs. |
| `picker` | `"auto"` | `auto`, `fzf-lua` or `select`. |
| `sidebar.side` | `"left"` | The edge the sidebar sits on, `left` or `right`. |
| `sidebar.width` | `40` | Columns the sidebar is held at. |
| `sidebar.view` | `"today"` | The view the sidebar opens. |
| `refresh_interval` | `60` | Seconds between the background reads behind `status()`. Floor of five. |
| `reminders` | `false` | Whether a task with a time raises a notification when it comes due. |
| `store` | `nil` | Passed as `--store`. `nil` leaves dam its own resolution. |
| `config` | `nil` | Passed as `--config`. `nil` leaves dam its own resolution. |
| `timeout` | `120` | Seconds one `dam` call may run before it is stopped. |
| `window.float` | `false` | Open the staging window as a centred float instead of a split. |

There is deliberately no option naming a credential.

## The Lua API

| Function | What it does |
| --- | --- |
| `require("damnit").setup(opts)` | Merge options. Optional. |
| `require("damnit").open_status()` | Open the staging window. Returns its buffer. |
| `require("damnit").open(name?)` | Open one view as a list. |
| `require("damnit").completed()` | Open the completed history. |
| `require("damnit").pick(name?)` | Search one view. |
| `require("damnit").toggle()` | Toggle the sidebar. |
| `require("damnit").status()` | The statusline string. |

`require("damnit.capture").capture(range?)` captures from the current buffer, and
`require("damnit.task_buffer").open(oid)` opens one object.

## Tests

```bash
nvim --headless --clean -l tests/run.lua            # everything
nvim --headless --clean -l tests/run.lua poll_spec  # one spec
stylua --check . && luacheck .
```

Every spec runs headless against a fake `dam` placed at the front of `PATH`, so no test reaches the
network, a real store or a real account. `tests/performance_spec.lua` times a full re-render and
warns rather than failing, because a timing assertion on a shared runner reddens a build on code
nobody touched.

## License

MIT. See [LICENSE](LICENSE).
