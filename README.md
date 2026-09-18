# todoist.nvim

Todoist from inside Neovim. So far: an async client for the Todoist API, a token that never touches
your configuration, a health check that proves both without printing the token, one task as an
editable buffer, every open task as a list you can name your own views of, one of those views as a
sidebar beside your work, and a task captured from the code in front of you that `gd` takes you back
to.

## Requirements

- Neovim with `vim.system`, `vim.uv`, `vim.uri_encode` and `vim.health`. Developed and tested on
  0.12.5.
- `curl` on your `PATH`.
- A Todoist API token, and somewhere to keep it that is not a file in your dotfiles. A password
  manager with a command line interface is the usual answer.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "webdavis/todoist.nvim",
  cmd = "Todoist",
  opts = {
    token_command = { "keepassxc-cli", "show", "--attributes", "Password", "<database>", "<entry>" },
    views = {
      today = "today | overdue",
      work = "#Work & !@waiting",
    },
  },
  keys = {
    { "<leader>tt", function() require("todoist").open() end, desc = "Todoist: every open task" },
    { "<leader>td", function() require("todoist").open("today") end, desc = "Todoist: today" },
    { "<leader>tb", function() require("todoist").toggle() end, desc = "Todoist: toggle the sidebar" },
    {
      "<leader>tc",
      function() require("todoist.capture").capture() end,
      desc = "Todoist: capture a task from here",
    },
    { "<leader>tc", ":Todoist capture<CR>", mode = "x", desc = "Todoist: capture this selection" },
  },
}
```

Or name an environment variable instead:

```lua
{
  "webdavis/todoist.nvim",
  opts = { token_env = "TODOIST_API_TOKEN" },
}
```

## The token

There are two ways a token reaches this plugin, and both of them are yours to name:

| Option          | What it is                                                            |
| --------------- | --------------------------------------------------------------------- |
| `token_command` | A command, as a list. Its first line of standard output is the token. |
| `token_env`     | The name of an environment variable holding the token.                |

There is no third way. The plugin will not read a token out of a configuration value, will not look
in a well-known file for one, and has no default location to fall back to, because a token in a file
is a token in a backup, in a diff and eventually in a public repository.

A resolved token is remembered for the session, so a vault command runs once rather than once per
request, and it is forgotten when `setup` runs again or when the API refuses it. It is handed to
curl on curl's standard input as a configuration file, which keeps it out of the process table. It
never appears in a message, a notification, a log line or the health report: those say that the
token resolved, and nothing else about it.

`token_command` failing is reported by its exit code alone. Its output is dropped rather than
quoted, in case a program printed the secret on the stream the error was read from.

## Options

| Option          | Default                          | What it does                                  |
| --------------- | -------------------------------- | --------------------------------------------- |
| `token_command` | unset                            | A command whose standard output is the token. |
| `token_env`     | unset                            | The name of an environment variable with it.  |
| `base_url`      | `https://api.todoist.com/api/v1` | The API root requests are built against.      |
| `curl`          | `"curl"`                         | The curl to run, found on `PATH` if bare.     |
| `timeout`       | `15`                             | Seconds a request may take before curl stops. |
| `views`         | `{}`                             | Named Todoist filter queries. See below.      |
| `sidebar`       | see below                        | The side, width and view of the sidebar.      |

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
require("todoist").setup(opts)

local client = require("todoist.client")

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
:Todoist task 6XGgmFVcrG5RRjVr
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
:Todoist                " every open task, grouped by project and section
:Todoist today          " one named view
```

```lua
require("todoist").open()         -- every open task
require("todoist").open("today")  -- one named view
```

`require("todoist").open` is the stable way in, so a keymap calls it rather than a command string.
It returns the buffer the list is in.

A view is a name and a Todoist filter query, declared in `setup`:

```lua
require("todoist").setup({
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
are declared. `:Todoist` completes them, alongside `capture`, `task` and `toggle`.

The list is a plain unlisted buffer in the current window, so every window command, search and motion
works on it. Two keys are bound in it:

| Key    | What it does                                        |
| ------ | --------------------------------------------------- |
| `<CR>` | Opens the task on this line as a task buffer.       |
| `R`    | Asks the API again for the view being shown.        |
| `gd`   | Jumps to the code the task was captured from.       |

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

### The same names in the herdr pane

[herdr-todoist](https://github.com/webdavis/herdr-todoist) declares its views as `[[views]]` entries
with a `name` and a `filter` in its plugin config, and this plugin declares them as the keys and
values of `views`. They are the same two things under different syntax, so the two configurations can
be read side by side: every `name` there is a key here, and the `filter` beside it is that key's
value, character for character. Keeping them equal is a convention rather than a mechanism, because
neither plugin reads the other's configuration, and the point of it is that one word opens one list
whichever of the two you are in.

## Capture from code

```vim
:Todoist capture              " on the cursor's line
:'<,'>Todoist capture         " from a visual selection
```

```lua
require("todoist.capture").capture()
```

A `TODO` you were never going to get back to becomes a task in your Inbox, and the description says
where it came from:

```text
todoist.nvim lua/todoist/sidebar.lua:112
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

| What it finds                                     | What it says                                     |
| ------------------------------------------------- | ------------------------------------------------- |
| No `path:line` anywhere in the description        | The task has no location.                         |
| A repository that is not the one you have open    | Names the one it wants and the one you are in.    |
| A file that has since moved or gone               | There is no file at that path.                    |
| A line past the end of the file                   | Opens it on the last line and says how long it is. |

The path is resolved against the repository the editor is in, which is the only base there is: the
description carries no absolute path, on purpose.

## The sidebar

```vim
:Todoist toggle
```

```lua
require("todoist").toggle()
```

A fixed-width vertical split on one edge of the tabpage, holding one view. A second call closes it.

```lua
require("todoist").setup({
  views = { today = "today | overdue" },
  sidebar = {
    side = "left",   -- or "right"
    width = 40,      -- columns
    view = "today",  -- a name from `views`
  },
})
```

`view` names a view, not a filter, so the same word opens the same list in the sidebar, in
`:Todoist today` and in the herdr pane. It has to be declared in `views`: a name this plugin was
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

## Health

```vim
:checkhealth todoist
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
