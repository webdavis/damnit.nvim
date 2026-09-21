# damnit.nvim

Todoist from inside Neovim. So far: an async client for the Todoist API, a health check, one task as
an editable buffer, every open task as a list you can name your own views of, one of those views as
a sidebar beside your work, a task captured from the code in front of you that `gd` takes you back
to, and the completed history a page at a time with `u` to reopen one.

## Requirements

- Neovim with `vim.system`, `vim.uv`, `vim.uri_encode` and `vim.health`. Developed and tested on
  0.12.5.
- `curl` on your `PATH`.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "webdavis/damnit.nvim",
  opts = {
    views = {
      today = "today | overdue",
      work = "#Work & !@waiting",
    },
  },
  keys = {
    { "<leader>tt", function() require("damnit").open() end, desc = "dam: every open task" },
    { "<leader>td", function() require("damnit").open("today") end, desc = "dam: today" },
    { "<leader>tb", function() require("damnit").toggle() end, desc = "dam: toggle the sidebar" },
    {
      "<leader>tc",
      function() require("damnit.capture").capture() end,
      desc = "dam: capture a task from here",
    },
    { "<leader>tc", ":Dam capture<CR>", mode = "x", desc = "dam: capture this selection" },
  },
}
```

## Options

| Option             | Default                          | What it does                                   |
| ------------------ | -------------------------------- | ---------------------------------------------- |
| `curl`             | `"curl"`                         | The curl to run, found on `PATH` if bare.      |
| `timeout`          | `15`                             | Seconds a request may take before curl stops.  |
| `views`            | `{}`                             | Named Todoist filter queries. See below.       |
| `picker`           | `"auto"`                         | `auto`, `fzf-lua` or `select`. See below.      |
| `sidebar`          | see below                        | The side, width and view of the sidebar.       |
| `refresh_interval` | `60`                             | Seconds between the fetches behind `status()`. |
| `reminders`        | `false`                          | Announce a task with a time when it comes due. |

Options are read when a request is made, so a later `setup` call changes the next request.

## Async, and what that means here

Every request is one curl process spawned through `vim.system` with a callback, and every result is
handed back inside `vim.schedule`. Nothing waits: `request` returns while curl is still running, and
a slow network cannot make the editor stop taking keystrokes. There is no synchronous variant,
because the moment one exists something calls it from a mapping.

A failure that might pass (no network, a server error, a rate limit) is retried once. A rate limit is
retried after the `Retry-After` seconds Todoist sent, bounded at ten seconds so a wait cannot read as
a hang. A refused token is not retried at all: the API's own guidance is that repeating an invalid
token only spends the rate limit, so instead the remembered token is dropped and the next request
asks its source again.

Whatever is left after that raises one `vim.notify` at `WARN`, carrying the API's own wording where
it gave any. A caller that would rather show the message itself passes `quiet = true` and reads the
error.

## Lua API

```lua
require("damnit").setup(opts)

local client = require("damnit.client")

client.get_task("6XGgmFVcrG5RRjVr", function(task, err)
  if err then
    return                      -- already notified, unless the request was quiet
  end
  vim.print(task.content)
end)

client.update_task("6XGgmFVcrG5RRjVr", { content = "Buy oat milk", priority = 3 }, function(task, err)
  -- content, description, due_string, priority and labels are what a task takes
end)
```

`client.request` is the one underneath, and adding an endpoint is a wrapper over it:

```lua
client.request({
  method = "GET",                                -- or POST, DELETE
  path = "/tasks/filter",                        -- appended to base_url
  query = { query = "today | overdue" },         -- percent-escaped for you
  body = nil,                                    -- a table, encoded as JSON
  quiet = false,                                 -- true suppresses the notification
}, function(data, err) end)
```

An error is a table, never a bare string, so a caller can act on the kind rather than on the
wording:

| `kind`         | What happened                                                    |
| -------------- | ---------------------------------------------------------------- |
| `token`        | No source was configured, or the source failed.                   |
| `network`      | curl produced no response: no route, no listener, or the timeout. |
| `unauthorized` | 401. The token was refused.                                       |
| `forbidden`    | 403. The account may not do this.                                 |
| `rate_limited` | 429, with `retry_after` when the API sent one.                    |
| `not_found`    | 404.                                                              |
| `http`         | Any other non-2xx, with `status`.                                 |
| `malformed`    | A 2xx body that is not JSON.                                      |

`message` is always safe to show a user.

## One task as a buffer

```vim
:Dam task 6XGgmFVcrG5RRjVr
```

The task arrives as a buffer: a header of `key: value` lines between two `---` fences, and the
description as the markdown body below them.

```markdown
---
content: Buy oat milk
due: tomorrow 9am
priority: 3
labels: errands, home
project: 2203306141
section:
---

The kind in the grey carton.

- [ ] check the date
```

That is markdown frontmatter, so the body highlights as markdown and the header is a block you can
retype by hand without guessing. `priority` is the API's own scale, where 4 is the most urgent and 1
is none. `labels` is a comma-separated list. `due` is the string Todoist parses, which is why a due
date it turned into a calendar date shows up as that date after a write.

`project` and `section` are the ids the task lives under, and they are shown rather than editable:
moving a task is a different call than editing one, so changing either is refused instead of
silently ignored.

`:w` writes it back. It sends only the fields that changed, so an unchanged `due` is left out
entirely rather than reparsed, which is what would otherwise drop a recurrence. A write that needs
nothing says so and marks the buffer written. `:q` on a buffer you have edited and not written goes
through Neovim's own unsaved-changes path, which is the `E37` refusal, or the prompt when you have
`'confirm'` set.

Two kinds of refusal, in the two places they belong. A header this plugin can be sure about is
refused here, before any request: an unknown or repeated field, a missing one, a header with no
fence, an empty `content`, a priority that is not 1 to 4, or a changed project or section. Each says
which line. Everything else is the API's to judge, the due string above all, and what comes back is
reported in the API's own wording.

The write is the same async request as every other, so nothing blocks while it is out. The buffer
stays modified until the API answers, which means an edit that has not landed still reads as
unwritten, and a rejected one leaves your text where you can fix it.

It works as the only thing in a fresh Neovim, which is how the herdr pane and the list views enter
it:

```bash
nvim +"Todoist task 6XGgmFVcrG5RRjVr"
```

## Lists and named views

```vim
:Dam                " every open task, grouped by project and section
:Dam today          " one named view
```

```lua
require("damnit").open()         -- every open task
require("damnit").open("today")  -- one named view
```

`require("damnit").open` is the stable way in, so a keymap calls it rather than a command string.
It returns the buffer the list is in.

A view is a name and a Todoist filter query, declared in `setup`:

```lua
require("damnit").setup({
  views = {
    today = "today | overdue",
    work = "#Work & !@waiting",
  },
})
```

The query is Todoist's own
[filter language](https://www.todoist.com/help/todoist/features/introduction-to-filters-V98wIH), the
one the app's Filters use, so whatever the app accepts is a view here. Nothing is parsed locally:
the query is sent as it is written, which is why a filter the API refuses comes back in the API's own
wording.

A name the plugin was never given is refused before any request, and the refusal says which names
are declared. `:Dam` completes them, alongside `capture`, `completed`, `task` and `toggle`.

The list is a plain unlisted buffer in the current window, so every window command, search and motion
works on it. These keys are bound in it:

| Key    | What it does                                        |
| ------ | --------------------------------------------------- |
| `<CR>` | Opens the task on this line as a task buffer.       |
| `R`    | Asks the API again for the view being shown.        |
| `gd`   | Jumps to the code the task was captured from.       |
| `x`    | Completes the task on this line.                    |
| `X`    | Reopens the task on this line.                      |
| `dd`   | Deletes the task on this line, after a confirm.     |
| `p`    | Cycles the priority one step up in urgency.         |
| `s`    | Sets the due date from a line you type.             |
| `l`    | Toggles a label from a picker.                      |
| `m`    | Moves the task to a project or section.             |
| `a`    | Adds a task from a line of Quick Add syntax.        |
| `u`    | Undoes the last complete or reopen.                 |
| `S`    | Sends this task to the agent, or to the clipboard.  |
| `za`   | Folds or unfolds the subtasks of this task.         |
| `>`    | Makes this task a subtask of the task above it.     |
| `<`    | Moves this task out from under its parent.          |

In the sidebar `<CR>` opens the task in the window beside it, so the list stays where it is.

A line maps back to its task through a table this plugin keeps, not by reading an id out of the text,
so the line can say whatever reads best. Headings hold no task and say so rather than opening the
nearest one.

```text
Todoist: today  (today | overdue)

Errands
  - Buy oat milk  (2026-09-17)  p3  @home
  Saturday
    - Collect the parcel  (2026-09-17)

Work
  - Review the branch  (2026-09-18)  p4
    - Read the diff
    - Leave the comments
```

A task carries a bullet and a heading does not. `p3` is the API's own priority scale, the same one the
task buffer shows, where 4 is the most urgent; priority 1 is no priority and is left off.

A view that matched nothing says `No tasks.`, which is a success. A filter the API refused says so
and quotes the API, so the two cannot be confused:

```text
Todoist: broken  (due befor: tomorrow)

The API refused this view:

  Invalid query
```

### Subtasks

A task with subtasks heads a tree, and each level is two spaces further in. A subtask is drawn under
its parent wherever the parent sits, so it appears once and never twice.

A view can match a subtask without matching its parent, which any filter narrower than the whole
account will do. Such a task heads a tree of its own at the top level rather than disappearing.

`za` folds a task's subtasks away and a second `za` brings them back. The whole subtree goes, not one
level of it, and the line says how many tasks went with it:

```text
Work
  - Review the branch  (2026-09-18)  p4  (+2)
```

Folding is this plugin's own, not Neovim's fold machinery, so `zR`, `zM` and the rest of the fold
family do not act on it. What that buys is the one thing that matters here: a fold is remembered by
task id for the session, and every write in this plugin re-reads the view, so a tree folded once
stays folded through a refresh, through a quick edit and through a change of view. Nothing is written
to disk, so a restart starts with everything unfolded.

`>` and `<` are writes, not a change of what is drawn. `>` makes the task a subtask of the task on
the row above it, whatever level that row is at, and `<` moves it out from under its parent: beside
the parent it just left when the view holds a grandparent, and to the top level of its section or
project when it does not. Todoist moves a task's own subtasks with it, so a branch keeps its shape.

Neither is undoable. `u` reverses a complete or a reopen and nothing else, so a `>` pressed by
mistake is put back with `<`, and a `<` with `>` on the row above where the task was.

Four cases send nothing and say why: `>` on the first task in the view, which has no row above it,
`>` on a task already under the task above it, `>` on the first task of a project or section other
than the one above it, and `<` on a task that is already at the top level.

### Completing a parent

`x` on a task with open subtasks in this view asks first, naming how many:

```text
Complete "Review the branch" and its 2 open subtasks? (Y)es, [N]o:
```

Yes or no, because Todoist closes a task's subtasks with it, server side, and offers no way to close
a parent and leave its subtasks open. Answering no sends nothing at all. A task with no open subtasks
in the view is completed with no question, which includes a parent whose children the current filter
did not match: the count is the view's own, and the server still closes them.

### Quick edits

The eight edit keys are [herdr-todoist](https://github.com/webdavis/herdr-todoist)'s eight, so a hand
that learned the pane knows the list. `x`, `X` and `p` act at once. `dd` asks yes or no first,
because Todoist keeps no undo for a delete. `s` and `a` ask for a line through `vim.ui.input`, and
`l` and `m` offer a picker through `vim.ui.select`, so whatever you have those configured to be is
what you get.

`s` and `a` are Todoist's own syntax, sent unparsed: `s` takes a due string (`tomorrow`, `next mon`,
`every 2 weeks`) and `a` takes a whole Quick Add line
(`Pay rent tomorrow 9am p1 #Finances @home`). The API reads them, so a line it cannot read comes
back in its own wording.

Every write is followed by a read of the view on screen, so what you are looking at came from the
server rather than from a guess at what the write did. A refused write leaves the lines where they
are and says what the API said.

### The undo

`u` reverses the last complete or reopen, and that is the whole of it:

- One level and no stack. A second complete replaces the first as the one `u` will reverse.
- Within the session only. Nothing is written to disk, so a restart starts with nothing to undo.
- Only a complete and a reopen. They are the pair with an exact opposite: a delete is gone, and a
  moved or relabelled task keeps no remembered previous state. After any other key, `u` says there
  is nothing to undo and sends nothing.
- A reversal the API refuses keeps the write remembered, so `u` can be pressed again, and re-reads
  the view so the buffer holds what the server holds rather than what the undo meant to do.

`u` in the completed history reopens the task on the line, which is the same word for the same act
from the other side: there, every line is already completed, so reopening one is what undoing means.
They are two buffers with their own keys, so neither shadows the other.

### Sending a task to the agent

`S` hands the task under the cursor to the agent working in this workspace. It asks for an optional
note first, through `vim.ui.input`: `<CR>` sends, `<Esc>` cancels, and an empty line sends the brief
with no note rather than refusing. Nothing here happens on its own.

The brief is plain text, because an agent pane is a shell rather than a structure. It is the same
text [herdr-todoist](https://github.com/webdavis/herdr-todoist) sends, character for character:

```text
Todoist task: file taxes
url: https://app.todoist.com/app/task/6cfCrxxxxxxxxxxx
due: 2026-09-20
priority: p1
labels: home, slow

receipts are in the drawer

note: start with the receipts
```

A field the task has nothing for is left out rather than written empty, so the brief carries no line
an agent has to discount. The URL is built from the task id: the v1 task object has no `url` field,
and `https://app.todoist.com/app/task/<id>` is the form the vendor documents in its place.

Inside herdr (`HERDR_ENV` set) the brief reaches the agent pane through `herdr pane send-text`, which
writes literal text into a pane's input without a return, so the agent holds the brief until you
submit it; `herdr agent focus` then puts the cursor there. It is sent as one bracketed paste, so a
multi-line brief is inserted verbatim instead of being read key by key, and a paste terminator inside
the text cannot end the frame early. A refused focus does not fail the send, since the brief is
already delivered.

WHICH pane is the agent pane comes from `herdr agent list`: a pane herdr names an agent for, in this
workspace, other than this one. The name it reports is the pane's name, then the agent running in it;
`display_agent` is the auth profile a pane signed in with, which two panes running different agents
can share, so it decides nothing.

A comment on the task then records the hand-off (`Handed to the agent <name> from the Neovim Todoist
list.`). It names the agent rather than its pane, which means nothing a day later, and WHEN is the
comment's own posted date, which Todoist stamps. A refused comment says `sent to <name>, comment
refused` rather than pretending the send failed: the agent has the work either way.

### When the agent pane cannot take it

Outside herdr, and whenever herdr cannot take the brief, the same text goes to the clipboard instead:
both the unnamed register and `+`, so it can be pasted with `p` here and with the system paste
anywhere else. Four cases reach it, and each says which in the notification:

| What happened                             | What you get                                            |
| ----------------------------------------- | ------------------------------------------------------- |
| `HERDR_ENV` is unset                      | The brief in the registers, at info level.              |
| `herdr` is missing, or the listing failed | The same, at warning level, with the command's message. |
| No agent pane in this workspace           | The same, saying so.                                    |
| herdr refused the send                    | The same, naming the pane it refused.                   |

The clipboard is a copy rather than a hand-off, so it writes no comment, and every one of those
notifications ends in `no hand-off comment written` so the two paths can never be confused. A build
with no clipboard provider, which is the normal state of a bare server, has no `+` register to write:
the brief goes to the unnamed register and the notification says `no clipboard provider` rather than
reading like a whole copy.

### The same names in the herdr pane

[herdr-todoist](https://github.com/webdavis/herdr-todoist) declares its views as `[[views]]` entries
with a `name` and a `filter` in its plugin config, and this plugin declares them as the keys and
values of `views`. They are the same two things under different syntax, so the two configurations can
be read side by side: every `name` there is a key here, and the `filter` beside it is that key's
value, character for character. Keeping them equal is a convention rather than a mechanism, because
neither plugin reads the other's configuration, and the point of it is that one word opens one list
whichever of the two you are in.

## Searching the tasks

```vim
:Dam pick                 " the view on screen, or every open task
:Dam pick today           " one named view, whatever is on screen
```

```lua
vim.keymap.set("n", "<leader>tf", function() require("damnit").pick() end)
```

| Key     | What it does                                    |
| ------- | ----------------------------------------------- |
| `<CR>`  | Opens the picked task as a task buffer.         |
| `<C-x>` | Completes the picked task and closes the picker. |

Each line carries the task's content, its due date, its priority, its labels and the project and
section it lives in, so any of those can be typed at.

### Which tasks it searches

With no argument the search follows the screen. A list buffer showing a filtered view is searched
inside that filter, the unfiltered list searches every open task, and with no list buffer in the
tabpage it searches every open task as well. Given a view name it searches that view whatever is on
screen, which is what a keymap bound to one view wants. The prompt always names the view and its
filter query, so a search that is holding tasks back says which filter is holding them.

### fzf-lua, or vim.ui.select

[fzf-lua](https://github.com/ibhagwan/fzf-lua) is optional and is never required at load: it is
looked up when a search is asked for, so installing it later needs no restart and not having it is
not an error. `picker` decides which front end opens:

| Value      | What it opens                                                                 |
| ---------- | ----------------------------------------------------------------------------- |
| `auto`     | fzf-lua when it loads, `vim.ui.select` otherwise. The default.                 |
| `fzf-lua`  | fzf-lua, or `vim.ui.select` with a notice saying fzf-lua is not installed.     |
| `select`   | `vim.ui.select`, whether fzf-lua is installed or not.                          |

`<C-x>` is an fzf-lua binding. `vim.ui.select` offers one choice and no second key, so on that path
selecting a task opens it and completing one is `x` in the list.

### Completing from the picker

`<C-x>` completes the picked task through the same path the list's `x` takes, asking the same yes or
no question over the tasks the search covered when the task is a parent with open subtasks in that
set; see "Completing a parent" above.

The picker closes, because fzf-lua's accept keys close it, and the list buffer re-reads the view
afterwards, so the task is gone from the list a moment later without the list guessing at what the
write did, and `u` in the list reverses a complete made here exactly as it reverses one made on a
line.

## Capture from code

```vim
:Dam capture              " on the cursor's line
:'<,'>Todoist capture         " from a visual selection
```

```lua
require("damnit.capture").capture()
```

A `TODO` you were never going to get back to becomes a task in your Inbox, and the description says
where it came from:

```text
damnit.nvim lua/todoist/sidebar.lua:112
```

That is the repository name, then the path inside it, then the line. The name is the directory the
`.git` lives in, so a linked worktree reports the worktree's own name and `gd` follows it back into
that worktree. The path is relative to the
repository root and never absolute: a description syncs to Todoist and onto your phone, so an
absolute path would put the layout of your machine there. A file in no repository goes out as its own
name and its line, with no repository in front of it, for the same reason. A buffer that is not a
file at all (a scratch buffer, a directory listing) has nowhere to point, so the task is made with no
description.

A visual selection becomes the content, by whole lines: the comment leader goes, a leading `TODO` or
`FIXME` goes with the `(author)` and punctuation after it, several lines join into one with their
space collapsed, and only the first line loses its marker. So this:

```lua
-- TODO(stephen): hold the width
--   the way nvim-tree does
```

captures as `hold the width the way nvim-tree does`. With no selection you are asked for the content
instead, on a prompt that starts on the current line's own words, so the common case is one key and
`<CR>`, and an answer you clear captures nothing.

Back in a list, a task carrying a location is marked with `⌖` at the end of its line, after the due
date, the priority and the labels, so it never pushes the content out of a narrow sidebar. `gd` on
such a task opens the file and puts the cursor on the line.

A description is text you can edit on your phone, so `gd` treats it as text somebody may well have
broken, and every case it cannot follow is a message rather than an error:

| What it finds                                  | What it says                                       |
| ---------------------------------------------- | -------------------------------------------------- |
| No `path:line` anywhere in the description     | The task has no location.                          |
| A repository that is not the one you have open | Names the one it wants and the one you are in.     |
| A file that has since moved or gone            | There is no file at that path.                     |
| A line past the end of the file                | Opens it on the last line and says how long it is. |

The path is resolved against the repository the editor is in, which is the only base there is: the
description carries no absolute path, on purpose.

## The completed history

```vim
:Dam completed
```

```lua
require("damnit").completed()
```

Completed tasks, newest first, a page at a time. Each line is the day it was finished and what it
was, and the list is flat: a finished task is read for when it was done rather than for where it was
filed. Two keys are bound in it:

| Key | What it does                                            |
| --- | ------------------------------------------------------- |
| `u` | Reopens the task on this line.                          |
| `R` | Reads the history again from today.                     |

The buffer is not modifiable, so `u` has no undo to take. A reopened task stops being completed, so
its line leaves the list at once; a refusal leaves every line where it is and reports the API's own
wording, which is what reopening a task that was never completed answers with.

### Paging, and why the first screen is one request

The endpoint reads completed tasks by completion date in a window of at most three months, paged by
cursor at fifty tasks a page. So the first screen is one page of the newest window, and the next page
is asked for when the cursor reaches the last task on screen, once. Nothing is asked for while a
request is out, and nothing is asked for once the walk has read as deep as it goes.

Depth is twelve windows of ninety days, about three years. At the bottom the list names the day it
read back to and says that is as far as the API goes, so an empty end reads as the end of the history
rather than as a list that stopped working.

An account whose recent months hold nothing costs several requests before the first task appears:
each window has to be asked for to find out it is empty. The list says `Reading completed tasks...`
the whole time and draws whatever it has, so those requests read as work rather than as a hang.

## The sidebar

```vim
:Dam toggle
```

```lua
require("damnit").toggle()
```

A fixed-width vertical split on one edge of the tabpage, holding one view. A second call closes it.

```lua
require("damnit").setup({
  views = { today = "today | overdue" },
  sidebar = {
    side = "left",   -- or "right"
    width = 40,      -- columns
    view = "today",  -- a name from `views`
  },
})
```

`view` names a view, not a filter, so the same word opens the same list in the sidebar, in
`:Dam today` and in the herdr pane. It has to be declared in `views`: a name this plugin was
never given is refused before the split is made, so a typo leaves your layout exactly as it was.
`today` is the default because it is the view worth having open while you work, and the default side
is the left at 40 columns, which is a file tree's width and reads the same way.

### How the width survives your layout

`winfixwidth`, which is what [nvim-tree](https://github.com/nvim-tree/nvim-tree.lua) and
[neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim) both put on their windows. A new split, a
closed window, `wincmd =`, `<C-w>=` and a resized terminal all leave a window carrying it at the
width it had. The sidebar also carries `winfixbuf`, so a command that opens a file cannot put that
file in the sidebar, and `<CR>` on a task opens the task in the window beside it instead.

One case `winfixwidth` cannot cover is the sidebar being the only window in its tabpage, where
Neovim has nowhere else to put the columns. A `WinNew` and `WinResized` autocommand puts the
configured width back the moment there is a second window to take the rest.

### Open, closed, and who decides

The sidebar is a window carrying a window-local flag, and that is the whole of what this plugin
remembers about it. Closing it with `:q`, `:close` or `<C-w>c` takes the flag with the window, so
the next toggle opens a new one rather than arguing that a sidebar is already there.

It is per tabpage. A toggle acts on the tabpage you are in: a sidebar in another tabpage is that
tabpage's window and is left alone, so every tabpage can have one, none, or its own.

While the first fetch is out the sidebar says which view it is holding and `Loading...` underneath,
the same as any list, so a slow network reads as a slow network rather than an empty window. Lines
are not wrapped, because a task belongs on one line even when the line is longer than the sidebar is
wide.

## The statusline

```lua
require("lualine").setup({
  sections = { lualine_x = { require("damnit").status } },
})
```

`status()` returns `3 due, 1 overdue`, or one half of that when only one half applies, or an empty
string when nothing is due. A component that returns an empty string draws nothing, which is the
right answer for "no news".

It is called on every redraw, so it does no work at all: it hands back a string that was built the
last time an answer arrived. One timer does the fetching, every `refresh_interval` seconds, and the
first call to `status()` is what starts it. A plugin nobody asks about polls nothing.

That makes the count up to `refresh_interval` seconds old, which is the trade for a component that
cannot stutter. Three readings are not counts:

| What you see | What it means                                          |
| ------------ | ------------------------------------------------------ |
| empty        | No fetch has finished yet, or nothing is due.          |
| `todoist !`  | The last fetch failed, or the token would not resolve. |
| a count      | What Todoist said at the last fetch.                   |

A count left standing after the network died is worse than no count, so a failure replaces the
number rather than keeping it.

A task due today at 09:00 is overdue from 09:00 on. A task due today with no time is due for the
whole of its day and overdue only once the day is over, because a full-day task names no moment to
be late by. Tasks due later than today are counted as neither.

## Due reminders

```lua
opts = { reminders = true }
```

Off unless you turn it on. With it on, a task that carries a time raises one `vim.notify` when its
time has come, once per task per due instant, and the next iteration of a recurring task counts as a
new instant. A full-day task never raises one, having no moment to announce.

It rides on the same fetch as the statusline, so there is one poller in this plugin, and turning
reminders on is what starts it when nothing has called `status()`. The lateness of an announcement
is therefore `refresh_interval` at worst.

A task completed before its time arrives is gone from the next fetch and is never announced. A task
whose time passed while Neovim was closed is not announced either: the first fetch after the timer
starts records what is already overdue and says nothing, so opening the editor in the evening does
not replay the morning. The timer stops on `VimLeavePre`, so nothing outlives the editor.

## Health

```vim
:checkhealth damnit
```

It reports whether curl was found, which source the token comes from, that the token resolved, and
that one authenticated request succeeded. It makes the cheapest request there is, because the only
way to know a token works is to use it. It reports nothing about the token's value, its length or
its first characters.

## Tests

```bash
nvim --headless --clean -l tests/run.lua
```

No spec talks to Todoist. Most drive the client through a fake `vim.system`; the rest run the real
curl against a loopback server the spec starts itself, which is what proves the command line is one
curl accepts and that a refused filter and an empty view come out different. A run needs no token and
reaches no network.

## License

MIT. See [LICENSE](LICENSE).
