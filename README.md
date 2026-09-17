# todoist.nvim

Todoist from inside Neovim. So far: an async client for the Todoist API, a token that never touches
your configuration, a health check that proves both without printing the token, and one task as an
editable buffer.

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
curl accepts. A run needs no token and reaches no network.

## License

MIT. See [LICENSE](LICENSE).
