# damnit.nvim design

`damnit.nvim` is the Neovim client of `dam`, the command-line tool of the `damnit` project. It
replaces `todoist.nvim`, which spoke to the Todoist API itself over curl.

The shape of the plugin follows from one fact: `dam` is a local, git-shaped task store with a
working layer, a stage, local commits and remotes. Tasks are now staged and committed the way
changes to source are, so the centre of the plugin is a status window modelled on vim-fugitive's,
and the network only moves when a push or a pull is asked for. That last part is what forces the
other headline change. Fugitive's `:Git push` takes the editor hostage while it runs. Nothing in
this plugin ever does.

Every claim below about `dam` cites either the design specification at
`damnit/docs/superpowers/specs/2026-09-18-damnit-design.md` (written `dam spec` plus a line number)
or the version-one code as built (written as a path under `crates/`, plus the observed command
output where the behaviour was measured on 2026-09-20 against `dam 0.1.0`). The error document,
the exit codes and the version range were re-read against `dam 0.2.0` on 2026-09-20, after that
release changed all three. Every claim about
fugitive cites `vim-fugitive/doc/fugitive.txt` or `vim-fugitive/autoload/fugitive.vim` by line.

______________________________________________________________________

## 1. Purpose and what changes

### The split

`dam` owns everything that used to make this plugin a network client:

- The Todoist API. `dam` core contains no Todoist code; a remote is reached through a helper found
  on `PATH` by name, `dam-remote-todoist` for `todoist::` (dam spec 258 to 273).
- The token. A helper declares the credentials it needs, and the remote's config table names a
  literal, a `_command` or a `_env` for each (dam spec 302 to 318). No token reaches the plugin, in
  any form, ever.
- The local copy. Reads run against SQLite at `~/.local/share/dam/dam.db` (dam spec 379), so a list
  is a local query rather than a request.
- Sync and history. `dam pull`, `dam push`, `dam log`, `dam commit`, `dam resolve`.
- The model. Categories, dependency cycles, completion blockers and recurrence are enforced by
  `dam` and refused with a reason (dam spec 30, 113 to 153).

`damnit.nvim` owns everything that is an editor:

- Editing a task as a buffer, and the diagnostics on a field the buffer got wrong.
- Staging: which working changes go into the next commit.
- The status window, its rendering, its folds and its keys.
- Pickers, named views, the sidebar, the statusline component and due reminders.
- The agent hand-off.
- Queueing and cancelling the `dam` processes it spawns, and never blocking on one.

### Every todoist.nvim feature and its fate

The fate is one of: kept as it is on `dam`, changed, moved into `dam`, dropped, or blocked on a
`dam` change that does not exist yet.

| Feature | Fate |
| --- | --- |
| Async curl client (`client.lua`) | Dropped |
| The three token options | Moved into dam |
| The eight client error kinds | Moved into dam |
| One task as a buffer | Changed |
| `project` and `section`, shown and not editable | Changed |
| Lists and named views | Changed |
| Todoist filter syntax | Changed |
| Subtask tree and `za` folding | Kept |
| `>` and `<` re-parenting | Changed |
| Completing a parent, with a confirm | Changed |
| Quick edits `x`, `p`, `s`, `l`, `m`, `a`, `dd` | Changed |
| Quick edit `X`, reopen | Blocked |
| The session undo, `u` | Dropped |
| Sending a task to the agent, `S` | Changed |
| The herdr pane name parity clause | Kept |
| Searching, fzf-lua or `vim.ui.select` | Kept |
| `<C-x>` completing from the picker | Kept |
| Capture from code, and `gd` back to it | Changed |
| The completed history and its paging | Changed |
| `u` reopening from the history | Blocked |
| The sidebar | Kept |
| The statusline component | Changed |
| Due reminders | Changed |
| `:checkhealth todoist` | Changed |
| The headless test harness | Kept |
| The stubbed-client test pattern | Changed |
| A fugitive-style staging window | New |
| A per-store operation queue | New |
| Conflict resolution | New |

The reason for each, in the same order.

- **Async curl client.** `dam` makes the requests; the plugin spawns `dam`. 478 lines deleted.
- **`token`, `token_command`, `token_env`.** Credentials live in `~/.config/dam/config.toml`
  (dam spec 302 to 318). 123 lines deleted with `token.lua`.
- **Error kinds `token`, `network`, `unauthorized`, `forbidden`, `rate_limited`, `not_found`,
  `http`, `malformed`.** The plugin maps `dam`'s exit code and its message instead. See section 3.
- **One task as a buffer.** Same frontmatter idea, new field set, new write path. See section 6.
- **`project` and `section`.** `dam` has one `path` field and `dam mv` moves an object
  (`crates/dam-cli/src/args.rs:142`), so `path` becomes editable and writes through `dam mv`.
- **Lists and named views.** A view is now a `dam` query, and dam's own saved filters are read
  alongside `opts.views` (dam spec 248 to 254).
- **Todoist filter syntax.** Replaced by dam's grammar, parsed by dam
  (`crates/dam-domain/src/query/parse.rs`).
- **Subtask tree and folding.** `dam` models the tree as `path` (dam spec 103 to 111); children are
  the objects nested under a parent's path (`crates/dam-application/src/use_cases/complete.rs`).
- **`>` and `<`.** Both become `dam mv`, which carries a subtree along
  (`crates/dam-application/src/use_cases/subtree.rs`).
- **Completing a parent.** `dam` refuses rather than cascading, so the confirm becomes an
  explanation and a choice. See section 6 and **Needed from dam**.
- **The seven quick edits that survive.** Each maps onto a `dam` verb. See section 7.
- **Quick edit `X`.** `dam` has no verb that reopens a completed task. See **Needed from dam**.
- **The session undo.** Superseded by the working layer: an uncommitted change is undone by
  discarding it in the window rather than by a one-level in-memory stack.
- **Sending a task to the agent.** The brief's fields change and the hand-off comment is dropped,
  because `dam` has no comments (dam spec 435).
- **The parity clause.** Still a convention rather than a mechanism, and now with a third source
  both clients can defer to. See section 7.
- **Searching, and the picker choice.** Unchanged, fed from `dam ls --json`.
- **`<C-x>` from the picker.** Unchanged, the same path as the list's `x`.
- **Capture and `gd`.** `dam new --body` carries the `repo path:line` location, and `gd` parses it
  back out of `body` instead of `description`.
- **The completed history.** `dam ls done --json` is one local query, so the cursor, the ninety-day
  windows and the twelve-window walk all go. 219 lines deleted.
- **`u` in the history.** The same missing dam verb as quick-edit `X`.
- **The sidebar.** Unchanged: `winfixwidth`, `winfixbuf`, one per tabpage.
- **The statusline component.** Same contract, fed by a `dam ls` poll.
- **Due reminders.** Same contract, same single poller, fed by the same `dam ls` poll.
- **The health check.** Now reports `dam`, its version, the store, the remotes and their credential
  sources. The credential half is superseded; see section 3.
- **The test harness.** Unchanged: `nvim --headless --clean -l tests/run.lua`.
- **The stubbed-client pattern.** A fake `dam` executable on `PATH` replaces a fake `vim.system`,
  which exercises the real spawn, argv, exit code and stderr. See section 9.
- **The staging window.** New, and the centre of the plugin. See section 4.
- **The operation queue.** New. See section 5.
- **Conflict resolution.** New: `dam resolve <oid> --ours` or `--theirs`, from the window.

______________________________________________________________________

## 2. Naming and migration

### Names

| Thing | Name |
| --- | --- |
| Repository | `webdavis/damnit.nvim` |
| Lua root module | `require("damnit")` |
| Lua submodules | `require("damnit.<name>")` |
| Command family | `:Dam` |
| Status window filetype | `damstatus` |
| Task buffer filetype | `damtask` |
| Commit message filetype | `damcommitmsg` |
| Highlight prefix | `Dam` |
| Autocommand group | `damnit` |

### Command map

| todoist.nvim | damnit.nvim | Note |
| --- | --- | --- |
| `:Todoist` | `:Dam list` | Every open task, as a list. |
| `:Todoist <view>` | `:Dam list <view>` | One named view. |
| `:Todoist task <id>` | `:Dam task <oid>` | One object as a buffer. |
| `:Todoist toggle` | `:Dam toggle` | The sidebar. |
| `:Todoist capture` | `:Dam capture` | Also takes a range, as today. |
| `:Todoist pick [<view>]` | `:Dam pick [<view>]` | The search. |
| `:Todoist completed` | `:Dam done` | The completed history. |
| none | `:Dam` | **The staging window**, the new default with no argument. |
| none | `:Dam cancel` | Cancel the running operation. See section 5. |

`:Dam` with no argument opening the status window mirrors `:Git` with no argument opening the
summary window (`fugitive.txt:22`). The task list moves to an explicit `:Dam list`, because the
window is now the thing you open first.

`:Dam` completes its subcommands and, after `list` or `pick`, the declared view names, the way
`:Todoist` completes today (`plugin/todoist.lua`).

The user command is declared in `plugin/damnit.lua` rather than behind `setup`, so
`nvim +"Dam task <oid>"` works in an editor holding nothing else, which is how a herdr pane and the
list buffer open one object.

### The repository

Rename `webdavis/todoist.nvim` to `webdavis/damnit.nvim` in place, on GitHub. A renamed repository
keeps a redirect for the old path, so an existing clone's `origin` and an unchanged lazy.nvim spec
both keep resolving. The rename is done in the same sitting as the first `damnit.nvim` release, not
before.

### The lazy.nvim spec in dotfiles

`dot_config/nvim/lua/plugins/todoist.lua` becomes `dot_config/nvim/lua/plugins/damnit.lua`. Every
part of it that exists to reach Todoist goes away:

```lua
-- damnit.nvim: the dam task store from inside the editor.
--
-- No token here, and no source for one. dam holds the Todoist credentials in
-- ~/.config/dam/config.toml, and this plugin only ever runs `dam`.
return {
  "webdavis/damnit.nvim",
  cmd = "Dam",
  opts = {
    views = {
      today = "due:today | overdue",
      upcoming = "due:this-week | due:next-week",
      dotfiles = "path:webdavis/dotfiles/ & !done",
    },
  },
  keys = {
    { "<leader>Ts", "<Cmd>Dam<CR>",         desc = "dam: the staging window" },
    { "<leader>Tt", "<Cmd>Dam list<CR>",    desc = "dam: every open task" },
    { "<leader>Td", "<Cmd>Dam list today<CR>", desc = "dam: today" },
    { "<leader>Tb", "<Cmd>Dam toggle<CR>",  desc = "dam: toggle the sidebar" },
    { "<leader>Tp", "<Cmd>Dam pick<CR>",    desc = "dam: search the tasks" },
    { "<leader>Th", "<Cmd>Dam done<CR>",    desc = "dam: the completed history" },
    { "<leader>Tc", "<Cmd>Dam capture<CR>", desc = "dam: capture a task from here" },
    { "<leader>Tc", ":Dam capture<CR>", mode = "x", desc = "dam: capture this selection" },
  },
}
```

The `<leader>T` group in `dot_config/nvim/lua/plugins/which-key.lua` is relabelled from `todoist` to
`dam`. Nothing else in the Neovim configuration changes.

The three view queries above are the dotfiles ones rewritten in dam's grammar. `today | overdue`
becomes `due:today | overdue`, `7 days` becomes `due:this-week | due:next-week`, and
`##webdavis & #dotfiles` becomes a `path:` prefix, because dam has no project-versus-parent
distinction to qualify: a project is a task with children and its identity is its path
(dam spec 103 to 111).

### The token leaves

The three token options (`token`, `token_command`, `token_env`) are deleted with no replacement.
This is the single largest reduction in the plugin, and it also removes a live defect: the operator's
current configuration carries a comment explaining that `vim.system` closes standard input, so an
interactive `keepassxc-cli` could never resolve a token from inside Neovim, and a macOS keychain read
stands in for it. That trade moves to `dam`, which documents the same constraint from its own side
(dam spec 375 to 377). See section 3 for what the plugin must still do about it.

### No compatibility shim

**No shim ships.** No `:Todoist` alias, no `require("todoist")` forwarding module, no
deprecation period. The plugin is pre-1.0 and has one user. A shim would have to translate Todoist
filter syntax into dam's grammar to be worth anything, and it cannot: `#Work & !@waiting` has no
mechanical translation into `path:` and `!label:`. A silent half-translation is worse than a command
that does not exist.

Decided 2026-09-20: no shim, the recommended option. Cost to reverse: one editing session re-typing
seven keymaps and three view queries, which is the diff shown above.

______________________________________________________________________

## 3. The dam boundary

### The contract

One module, `damnit.dam`, is the only code in the plugin that spawns a process. Everything else
calls it. The rules it enforces:

1. **Argv, never a shell string.** Every call is `vim.system({ "dam", ... }, opts, on_exit)`. There
   is no `vim.fn.system`, no `io.popen`, no `:!`, and no string that a shell would re-read. A task
   subject holding a quote, a semicolon or a newline is an argument and nothing else.
1. **`--json` on every call, without exception**, including the ones whose result is discarded. The
   human renderings in `crates/dam-cli/src/output.rs` are for a terminal and are not a contract.
1. **One `vim.system` call per user action.** A key press spawns at most one `dam`. Where an action
   needs two (stage then commit), they are two entries in the queue of section 5, not one call that
   waits for another.
1. **`vim.system(...):wait()` is forbidden outside `tests/`.** It is grep-checked in CI. The one
   exception is `:checkhealth`, which runs inside `vim.wait` for the same reason `todoist.nvim`'s
   health check does today (`lua/todoist/health.lua:19`), and which is entered deliberately.
1. **Every result is marshalled by `vim.schedule`** before it touches a buffer, a window or an
   option. A `vim.system` callback runs on the libuv loop, where most API calls are not allowed.
1. **The plugin never opens a socket, a file handle on the store, or a network connection.** It does
   not read `dam.db`. SQLite in WAL mode with mode 0600 (dam spec 379) is dam's, and a second reader
   would be a second writer's problem the day one exists.

### The call table

Every `dam` invocation the plugin makes, with the argv it builds. `<S>` stands for the resolved
store arguments, which are `{ "--store", opts.store }` when `opts.store` is set and nothing
otherwise, so dam's own default and the `DAM_STORE` environment variable keep working
(`crates/dam-cli/src/args.rs:18` to `21`).

| Action | argv |
| --- | --- |
| Version handshake | `dam --version` |
| Read status | `dam <S> status --json` |
| Read unstaged changes | `dam <S> diff --json` |
| Read staged changes | `dam <S> diff --staged --json` |
| Read commits | `dam <S> log --json` |
| Read one object | `dam <S> show <oid> --json` |
| List a view | `dam <S> ls <query> --json` |
| Stage | `dam <S> add <oid>... --json` |
| Stage everything | `dam <S> add -A --json` |
| Unstage some | `dam <S> reset <oid>... --json` |
| Unstage everything | `dam <S> reset --json` |
| Commit | `dam <S> commit -m <message> --json` |
| Push | `dam <S> push [<remote>] --json` |
| Pull | `dam <S> pull [<remote>] --json` |
| Resolve a conflict | `dam <S> resolve <oid> --ours --json` or `--theirs` |
| Create | `dam <S> new <subject> [--path ...] [--due ...] [-p N] [--label L]... [--body B] --json` |
| Complete | `dam <S> done <oid> [--force] --json` |
| Edit fields | `dam <S> edit <oid> <field flags> --json`, see section 6 for the field map |
| Move | `dam <S> mv <oid> <path> --json` |
| Remove | `dam <S> rm <oid> --json` |
| List remotes | `dam <S> remote list --json` |

Every flag above is from `crates/dam-cli/src/args.rs`, confirmed against `dam <verb> --help`.

### The JSON shapes the plugin depends on

Measured on 2026-09-20 by running the built binary against a scratch store. These five are the
window's entire input.

`dam status --json` (`crates/dam-cli/src/commands/status.rs:36`):

```json
{
  "staged":    [ <change>, ... ],
  "unstaged":  [ <change>, ... ],
  "conflicts": [ { "oid": "<40 hex>", "remote": "<name>", "ours": <object>, "theirs": <object> } ],
  "notices":   [ <notice>, ... ],
  "unpushed":  [ { "remote": "<name>", "commits": 1 } ]
}
```

A `<change>` is a flat row: `{ "oid", "op": "create"|"update"|"delete", "fields": ["subject", ...]
}` followed by the object's own columns, `kind`, `subject`, `path`, `labels`, and then `done`,
`priority`, `due` for a task or `start`, `end` for an event. `before` and `after` hold the whole
`<object>` on each side and are present **only under `--full`**, which this plugin never passes
(`crates/dam-cli/src/commands/status/rows.rs`, and section 5 of **Needed from dam** below). The
object columns are absent only where a change has neither side.

A `<notice>` carries a `kind` of `removed_upstream`, `event_cancelled`, `push_failed`, `pull_failed`
or `kind_changed`, each with its own fields (`crates/dam-cli/src/commands/status.rs:167`):
`removed_upstream` has `remote`, `oid`, `subject`; `event_cancelled` has `oid`, `subject`,
`attached`; `push_failed` has `remote`, `oid`, `why`; `pull_failed` has `remote`, `why`;
`kind_changed` has `oid`, `ours`, `theirs`.

`dam remote list --json` is `{ "remotes": [ { "name", "helper", "url", "path", "stale_seconds" } ]
}`. The key is `name`; `remote` is what the `unpushed` rows above use for the same thing. An
`unpushed` row is written for every configured remote, including one with `"commits": 0`, which the
human form filters out.

An `<object>`, which `conflicts` embeds on both sides and a change carries only under `--full`, is
the wire object from `crates/dam-application/src/wire.rs`:

```json
{
  "oid": "78b8950b02735107aa608659dcf19f6f50adfeb1",
  "kind": "task",
  "subject": "buy oat milk",
  "body": "",
  "path": "inbox/",
  "labels": ["errand"],
  "depends": [],
  "reminders": [],
  "task": { "done": false, "priority": 1, "due": "2026-09-25" }
}
```

`recurrence`, `task.deadline`, `task.event` and the whole `event` table are omitted when unset
(`crates/dam-protocol/src/messages.rs:104` to `162`).

`dam diff --json` is `{ "changes": [ <change>, ... ] }`.
`dam log --json` is `{ "commits": [ { "id", "at", "message", "changes": [...] } ] }`.
`dam push --json` is `{ "remotes": [ { "remote", "sent", "succeeded", "skipped", "failed": [ {
"oid", "why" } ] } ] }`.
`dam pull --json` is `{ "remotes": [ { "remote", "created", "updated", "unchanged", "conflicts",
"removed_upstream" } ] }`.

An `oid` is always the full forty hex characters in JSON, and `dam` accepts a prefix of at least
four (`crates/dam-cli/src/oids.rs:6`). The plugin always sends the full `oid` it read, so a prefix
collision cannot happen, and it renders the first seven, which is what `dam`'s own human output
shows (`Oid::short`).

### The version handshake

On the first call of a session, before any other, the plugin runs `dam --version` and reads the
version out of `dam <major>.<minor>.<patch>`. The supported range for version one of the plugin is
`>= 0.2.0` and `< 0.3.0`, because the error document this plugin reads arrived in dam 0.2.0 and a
0.1.x writes prose instead.

- **Given** `dam --version` prints `dam 0.2.0`, **when** the handshake runs, **then** the version is
  recorded for the session and the pending action proceeds.
- **Given** `dam --version` prints a version outside the range, **when** the handshake runs, **then**
  every action is refused for the session with
  `damnit.nvim: dam 0.1.0 is outside the supported range >=0.2.0 <0.3.0; update damnit.nvim` and no
  further `dam` process is spawned until `setup` runs again.
- **Given** `dam` is not on `PATH`, **when** the handshake runs, **then** the refusal is
  `damnit.nvim: dam was not found on PATH; install it with cargo install damnit` and the window is
  not opened.
- **Given** `dam --version` prints something the plugin cannot parse, **when** the handshake runs,
  **then** the plugin warns once and proceeds. An unreadable banner is not a reason to refuse to
  work; a wrong JSON shape will fail loudly at the call that needs it.

The handshake is one extra process per session, measured at the same cost as any other `dam` call.
It is not re-run per action.

`vim.system` throws when the binary is absent rather than calling back, so the spawn is wrapped in
`pcall`, exactly as `todoist.nvim` wraps curl today (`lua/todoist/client.lua:218`).

### Error mapping

Under `--json`, `dam` writes one error document on standard error and nothing else there, and
standard output stays empty (dam spec 504 to 546). A run that succeeds writes nothing on standard
error at all.

```json
{"error": {"kind": "refused", "rule": "blocked",
 "message": "98d8780 cannot be completed:\n  child a9db854 is open\nuse --force to complete it
anyway, or --force --interactive to decide what happens to them",
 "oids": ["98d878013fb0e026d37170e7ceed6707192ae99a",
          "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77"]}}
```

`kind` is one of `refused`, `store`, `helper`, `credential`, `parse`, `usage` and `cancelled`.
`rule` names the rule a refusal broke, one stable snake_case word per rule, and is null for every
other kind. `oids` names the objects the message names, in the order it names them, in full.

`message` is the sentence the human form prints after `dam: `, carried verbatim
(`crates/dam-cli/src/error.rs:86` sends `self.to_string()`), so it is one line for most failures and
several for a refusal that lists what stands in the way. A blocked completion is a header line, one
indented line per blocker, and a closing line of advice aimed at a terminal
(`crates/dam-application/src/errors.rs:113`). A plugin that shows it shows all of it, which is why
the blockers are read from `oids` rather than from the sentence.

The exit code says the same thing more coarsely, and the two agree:

| Exit | Meaning | Plugin kind |
| --- | --- | --- |
| 0 | Success, JSON on standard output | none |
| 1 | `dam` failed: store, config, helper, credential, editor, parse or io | `error` |
| 2 | The command line was wrong, which is clap's own usage text and no document | `error` |
| 3 | Cancelled: an interrupt, or a prompt that could not be answered | `cancelled` |
| 4 | A rule `dam` keeps refused the action, and `rule` names it | `refused` |
| 124 | The plugin's own `vim.system` timeout fired, sending TERM | `timeout` |

Exit 4 is every rule and nothing else, so the plugin maps the code once rather than per verb, and
exit 2 is the command line alone.

The plugin's error table is `{ kind, code, rule, oids, message }`: the kind from the table above,
the exit code, the document's `rule` and `oids` where it carried them, and the document's own
`message`. `message` is always safe to show: dam's own rule is that no error message contains a
token (dam spec 396). A signal or a timeout is the plugin's own verdict rather than dam's, so those
two keep the plugin's kinds and its own sentence.

The plugin matches no substring of a message. Standard error that is not a document, which is what
clap prints for an argument `dam` rejects before it runs, is carried verbatim as the message with
no `rule` and no `oids`. dam's prose is not a contract, and a message that changes wording must not
change what the plugin does.

### The three failure modes named in the brief

**dam is missing.** `vim.system` throws; the `pcall` catches it; every command refuses with the
install line above. `:checkhealth damnit` reports it as an error. No window opens, so there is no
half-drawn buffer to close.

**The store is locked.** SQLite in WAL mode allows one writer at a time. A second `dam` writing
concurrently fails with a storage error, which reaches the plugin as exit 1 with `kind` `store` in
the document (`crates/dam-application/src/errors.rs`, `UseCaseError::Store`). The per-store queue of
section 5 is what prevents the plugin from being that second writer against itself. A lock held by
something outside Neovim is reported as it arrives, and the window offers `R` to try again. The
plugin does not retry a storage error on its own: a busy database is a signal, and a silent retry
loop turns a visible conflict into a hang.

**A remote is unreachable.** `dam push` and `dam pull` reach the remote through a helper process
(dam spec 258 to 273). A network failure arrives as `the remote refused: <text>` or
`talking to the helper: <text>`, exit 1 with `kind` `helper`, after however long the helper took. A
remote's config may set a `deadline`, which is how long one helper response may take before the
helper is killed (`crates/dam-application/src/config.rs`, `RemoteConfig::deadline`). The plugin sets
its own `vim.system` timeout as well, at `opts.timeout` seconds, default 120, so a helper with no
configured deadline cannot leave a queue entry running forever. On timeout `vim.system` sends TERM
and reports code 124, and the plugin reports
`damnit.nvim: dam pull took longer than 120s and was stopped`.

A `pull` failure during a stale-read is not an error at all: `dam` records it as a notice and the
read succeeds (`crates/dam-cli/src/commands/remote.rs`, `maybe_pull_stale`). So the window shows it
in the Notices section rather than as a failed command.

### Two traps the plugin must handle, both from dam's own design

**A read can pull.** `dam ls` and `dam show` call `maybe_pull_stale` before they answer
(`crates/dam-cli/src/commands/ls.rs`, `crates/dam-cli/src/commands/show.rs`). A remote with `stale`
set in config makes a read pull that remote first when the last pull is older than the value
(dam spec 372). So a `dam ls` behind the statusline poll, the sidebar or a picker **can** make a
network call, and can take as long as the network takes.

This does not break the non-blocking model, because every one of those calls already goes through
`vim.system` with a callback. It does mean the plugin must not treat a read as cheap: reads go in the
queue like everything else, reads carry the same timeout, and the statusline shows a read in flight.
`dam status` does not pull (`crates/dam-cli/src/commands/status.rs:9`), which is why the window
re-renders from `status` rather than from `ls`. See **Needed from dam** for the `--no-pull` flag
that would let the plugin ask for a guaranteed-local read.

**A credential command cannot prompt.** `dam` resolves a `_command` credential by running it with
dam's own standard input inherited, and the dam specification says plainly that a vault CLI which
prompts for a password works when `dam` runs in a terminal and fails when a client spawns `dam` with
standard input closed (dam spec 375 to 377). `vim.system` closes standard input unless `stdin` is
given, so **every push and pull from this plugin hits that case**.

The plugin's answer is to name it rather than to work around it. A push or pull that fails with a
credential error gets one extra sentence:

```
damnit.nvim: the remote's credential command needs a terminal; run dam push in one,
or point the credential at a non-interactive source.
```

`:checkhealth damnit` warns when any configured remote resolves a credential through `_command`,
because that is the configuration in which push from the editor will fail, and the warning is worth
more before the first push than after it.

**Superseded by dam 0.2.0 (task 26 ruling):** `dam remote list --json` reports `name`, `helper`,
`url`, `path`, `stale_seconds`, `last_pull` and `last_push` and nothing about a credential, so the
plugin has no data to warn from and the check is not built. The same supersession applies to the
summary bullet in section 1 and to the Credential sources row of the health table below.

### Where dam's store and config live

The plugin reads neither, and it hardcodes neither. Defaults are dam's:
`~/.local/share/dam/dam.db` for the store and `~/.config/dam/config.toml` for the config
(dam spec 343, 379). Both are overridable with `--store` and `--config`, which are global flags that
also read `DAM_STORE` and `DAM_CONFIG` from the environment (`crates/dam-cli/src/args.rs:18`).

`opts.store` and `opts.config`, both unset by default, are passed through when set. When both are
unset the plugin passes neither flag, so dam's own resolution and the environment still apply. The
window's identity is the store: `opts.store` when set, else the value of `DAM_STORE`, else the
literal string `default`. One status buffer per such key.

______________________________________________________________________

## 4. The staging window

`:Dam` opens one buffer per store, named `damnit://status/<key>`, filetype `damstatus`, in a split.
A second `:Dam` for the same store focuses the existing window rather than opening a second one,
which is what `:Git` does (`fugitive.txt:22` to `25`).

The buffer is `nomodifiable`, `nobuflisted`, `bufhidden=hide`, `buftype=nofile`, `noswapfile`. It is
re-rendered in full from a fresh `dam status --json`; nothing patches it in place. Being unmodifiable
is a change from fugitive, whose summary buffer is modifiable so that inline diffs can be inserted;
here the inline diff is drawn with extmarks instead and nothing needs the buffer writable.

### Sections

| Section | What it holds | Source |
| --- | --- | --- |
| Working | Changes since the last commit that are not staged, one line per object | `status.unstaged` |
| Staged | Changes that will go into the next commit | `status.staged` |
| Unpushed | Per remote, the commits not sent yet | `status.unpushed` plus `dam log --json` |
| Notices | What the remotes reported: removals, cancellations, failures | `status.notices` |
| Conflicts | Objects both sides changed, with the two subjects | `status.conflicts` |

Fugitive's sections are Head and Push as headers, then Rebasing, Reverting or Cherry Picking,
Untracked, Unstaged, Staged, Unpushed and Unpulled
(`vim-fugitive/autoload/fugitive.vim:2973` to `3015`). Four of those have no meaning here. There is
no Untracked section because `dam new` puts an object straight into the working layer, so there is
nothing corresponding to a file git has never seen. There is no Rebasing, Reverting or Cherry
Picking section because `dam` has no such operations (dam spec 178 to 232). Unpulled becomes
Notices, because `dam pull` does not leave unmerged remote commits to look at: it merges, marks
conflicts and records notices (dam spec 328 to 339).

Conflicts is listed last in the table and rendered **first**, above Working, because it is the only
section that blocks a push: `dam` refuses a pull while conflicts are unresolved
(`Refusal::UnresolvedConflicts`, `crates/dam-application/src/errors.rs`).

An empty section is omitted entirely, the way `dam status` itself omits one
(`crates/dam-cli/src/commands/status.rs:65`). A status with nothing in any section renders the
header plus one line, `nothing staged, nothing changed`, which is dam's own wording for it.

### The header

Four lines, before the first section, modelled on fugitive's Head and Push headers
(`autoload/fugitive.vim:2973`, `:2976`):

```
Store:   ~/.local/share/dam/dam.db
Remotes: todoist (1 unpushed)  gcal (clean)
Running: push todoist  12.3s     [C-c to cancel]
Help:    g?
```

- `Store` is the resolved store path, with the home directory shown as `~`.
- `Remotes` is one entry per configured remote from `dam remote list --json`, each with its unpushed
  commit count from `status.unpushed`. No remotes configured renders `Remotes: none configured`.
- `Running` is present only while an operation is in flight, and carries the elapsed time, updated
  every 250 ms. See section 5.
- `Help` mirrors fugitive's `Help: g?` header, which fugitive emits unless `advice.statusHints` is
  off (`autoload/fugitive.vim:2985`).

### A change line

```
  changed  78b8950  buy oat milk           (subject, due, labels)  inbox/
  new      660a08d  write the spec                                 work/
  removed  a9db854  child                                          work/proj/
```

The three verbs and the seven-character oid are dam's own human rendering
(`crates/dam-cli/src/commands/status.rs:80`). What the plugin adds is the field summary in
parentheses for an update, computed by comparing `before` and `after`, and the path at the end.

The field summary is the one thing the plugin derives rather than reads. `dam` has the answer
already, in `changed_fields` (`crates/dam-domain/src/change.rs`), and uses it for its own human
line, but does not put it in `change_json`. Until it does (see **Needed from dam**) the plugin
compares the two wire objects field by field, in the order `subject`, `body`, `path`, `labels`,
`depends`, `reminders`, `recurrence`, then the task or event fields, which is `changed_fields`'
own order. The comparison lives in one function with a golden test per field, so a drift from dam's
list is a red test rather than a wrong label.

### Keys

Where a fugitive key's meaning carries over, it is the same key. Where it does not, the key is not
reused for something else.

| Key | What it does | Fugitive |
| --- | --- | --- |
| `-` | Stage or unstage the object under the cursor, or a visual range | `fugitive.txt:296` |
| `s` | Stage the object under the cursor or the visual range | `fugitive.txt:290` |
| `u` | Unstage the object under the cursor or the visual range | `fugitive.txt:293` |
| `U` | Unstage everything | `fugitive.txt:299` |
| `X` | Discard the working change under the cursor, after a confirm | `fugitive.txt:302` |
| `=` | Toggle an inline field diff of the change under the cursor | `fugitive.txt:310` |
| `<CR>` | Open the object as a task buffer | `fugitive.txt:354` |
| `cc` | Commit, through a message buffer | `fugitive.txt:466` |
| `P` | Push | `fugitive.txt:382`, where `P` populates a `:Git push` line in the Unpushed section |
| `p` | Pull | none; see below |
| `R` | Re-read the status | none; see below |
| `gu` | Jump to the Working section | `fugitive.txt:441` |
| `gs` | Jump to the Staged section | `fugitive.txt:448` |
| `gp` | Jump to the Unpushed section | `fugitive.txt:451` |
| `gn` | Jump to the Notices section | none |
| `gc` | Jump to the Conflicts section | none |
| `co` / `ct` | Resolve the conflict under the cursor with ours or theirs | none |
| `<C-c>` | Cancel the running operation | none |
| `q` | Close the window | `fugitive.txt:589` documents `gq`; `q` is bound here as well |
| `g?` | Show the help | `fugitive.txt:596` |

Three notes on the divergences.

`p` for pull takes a key fugitive uses for "open in a preview window" (`fugitive.txt:374`). There is
no preview window concept here, so the key is free, and `P` and `p` as the push and pull pair is
what a hand expects next to each other. `gP` stays unbound rather than being given to pull, so that
a finger trained on fugitive's `gP` (jump to Unpulled) does not trigger a network operation.

`R` re-reads. Fugitive deliberately does **not** do this: its `R` prints
`Reloading is automatic. Use :e to force` (`autoload/fugitive.vim:2719`). Reloading is not automatic
here, because the status is the output of a process rather than a view of the filesystem, and
`todoist.nvim` already trains `R` as refresh in both its list and its history buffers. So `R` keeps
that meaning, and `:e` is bound to the same function so a fugitive hand lands somewhere sensible.

`X` is limited in version one. See the scenario below.

### Given, when, then

**`-`, `s` and `u`, staging.**

- Given the cursor is on a change in Working, when `-` is pressed, then `dam add <oid> --json` is
  queued, and on success the window re-renders from a fresh `dam status --json` and the cursor stays
  on the same oid, now in Staged.
- Given the cursor is on a change in Staged, when `-` is pressed, then `dam reset <oid> --json` is
  queued and the object returns to Working.
- Given the cursor is on a section heading, when `-` is pressed, then every object in that section is
  staged or unstaged in one call (`dam add <oid> <oid> ...`), because `add` and `reset` both take a
  list (`crates/dam-cli/src/args.rs:155`, `:163`).
- Given a visual range covering three changes and one heading, when `-` is pressed, then the three
  changes are staged in one call and the heading contributes nothing.
- Given the cursor is on a Notices or Conflicts line, when `-`, `s` or `u` is pressed, then nothing
  is sent and the message is `damnit.nvim: nothing to stage on this line`.
- Given the cursor is on a change in Staged, when `s` is pressed, then nothing is sent and the
  message is `damnit.nvim: already staged`. `s` stages and `u` unstages, each one direction only,
  which is what makes `-` worth having.
- Given `dam add` exits non-zero, when the callback runs, then the message is shown at `WARN`, the
  window re-renders anyway, and the cursor is restored. The window always shows what `dam` holds,
  never what a refused write intended.

**`U`, unstage everything.**

- Given anything is staged, when `U` is pressed, then `dam reset --json` with no oids is queued,
  which unstages everything (`crates/dam-cli/src/commands/stage.rs`, `run_reset` with an empty list),
  and the window re-renders.
- Given nothing is staged, when `U` is pressed, then nothing is sent and the message is
  `damnit.nvim: nothing is staged`.

**`X`, discard a working change.**

`dam` has no verb that restores an object to its committed state. There is no `restore`, no
`checkout` and no `reset --hard`; grepping the whole workspace for those words finds nothing outside
tests. So `X` ships in version one only for the case where `dam` does have an exact inverse.

- Given the cursor is on a change whose `op` is `create`, when `X` is pressed, then the prompt is
  `Discard "buy oat milk"? This removes the object. (y/N)`, and on `y` the plugin queues
  `dam rm <oid> --json`, which is `create`'s exact inverse: the object was never committed, so
  removing it from the working layer leaves nothing behind.
- Given the cursor is on a change whose `op` is `update` or `delete`, when `X` is pressed, then
  nothing is sent and the message is
  `damnit.nvim: dam has no verb that restores a committed object; commit the change or edit it back`.
- Given the confirm is answered `n` or `<Esc>`, when the prompt closes, then nothing is sent and the
  window is unchanged.

There is no undo for the `create` case either. `dam rm` moves the object out of the working layer,
and no dam verb brings it back. The confirm is therefore not optional and has no "do not ask again"
setting. See **Needed from dam** for the `dam restore` that would make `X` whole and undoable.

**`=`, the inline field diff.**

- Given the cursor is on a change whose `op` is `update`, when `=` is pressed, then virtual lines are
  attached below that line, one per changed field, showing the old and new values, and a second `=`
  removes them.
- Given the change is a `create`, when `=` is pressed, then the virtual lines show every set field of
  `after` with no old column.
- Given the change is a `delete`, when `=` is pressed, then the virtual lines show every set field of
  `before`, dimmed, with no new column.
- Given a diff is open and the window re-renders, when the new lines are drawn, then the diff is
  re-opened on the same oid if that oid is still present, and forgotten otherwise. Open diffs are
  remembered by oid for the session, the way `todoist.nvim` remembers folds by task id.

The rendering, using `nvim_buf_set_extmark` with `virt_lines`:

```
  changed  78b8950  buy oat milk           (subject, due, labels)  inbox/
           subject  oat milk           ->  buy oat milk
           due      -                  ->  2026-09-25
           labels   home               ->  errand, home
```

Fugitive's `=` inserts a real text diff into the buffer (`fugitive.txt:310`, `:313`, `:316`, and the
`>` and `<` that insert and remove one). Virtual lines are used instead for three reasons: the buffer
stays unmodifiable, the line numbers of every other entry stay stable so a remembered cursor position
survives, and there is no real diff to insert, because a change here is a set of field pairs rather
than a hunk of text.

**`<CR>`, open the object.**

- Given the cursor is on a change, when `<CR>` is pressed, then the object opens as a task buffer
  (section 6) in the window this one was opened from, or in a split when the status window is the
  only one.
- Given the cursor is on a Conflicts line, when `<CR>` is pressed, then two task buffers open in a
  vertical split, ours on the left and theirs on the right, both unmodifiable, built from
  `conflicts[].ours` and `conflicts[].theirs`, which `dam status --json` already carries in full.
- Given the cursor is on an Unpushed commit line, when `<CR>` is pressed, then the commit opens as a
  read-only buffer listing its changes, from `dam show <commit-id> --json`.
- Given the cursor is on a heading or a Notices line, when `<CR>` is pressed, then nothing happens.

**`cc`, commit.**

- Given something is staged, when `cc` is pressed, then a scratch buffer named
  `damnit://commit/<key>`, filetype `damcommitmsg`, opens in a split, carrying an empty first line
  and then the staged changes as comment lines prefixed `# `, the way `COMMIT_EDITMSG` carries the
  status. The cursor starts on line one in insert mode.
- Given the message buffer holds text, when `:w` is written, then the comment lines are stripped, the
  remainder is trimmed, and `dam commit -m <message> --json` is queued. On success the buffer is
  wiped, the status window re-renders, and the notification is
  `damnit.nvim: 7257572 committed, 2 changes`, built from the commit report's `id` and the length of
  its `changes` array (`crates/dam-cli/src/commands/commit.rs`, `commit_json`).
- Given every line is a comment or blank, when `:w` is written, then nothing is sent and the message
  is `damnit.nvim: no commit message; the commit was not made`, and the buffer stays open.
- Given nothing is staged, when `cc` is pressed, then no buffer opens and the message is
  `damnit.nvim: nothing is staged to commit`.
- Given the message buffer is closed with `:q` unwritten, when it closes, then nothing is sent.

Write-to-commit rather than quit-to-commit, because `dam commit -m` takes the message as an argument
and there is no file for dam to read (`crates/dam-cli/src/args.rs:168`). The buffer is the plugin's
own editing surface, not something dam opened.

**`P`, push.**

- Given at least one remote has unpushed commits and no operation is running, when `P` is pressed,
  then `dam push --json` is queued for every remote, the header gains its `Running` line, and the
  editor stays fully responsive. See section 5 for the whole model.
- Given the cursor is on a remote's line in Unpushed, when `P` is pressed, then only that remote is
  pushed: `dam push <remote> --json`.
- Given an operation is already running, when `P` is pressed, then nothing is queued and the message
  is `damnit.nvim: push todoist is already running; C-c cancels it`.
- Given nothing is unpushed, when `P` is pressed, then nothing is sent and the message is
  `damnit.nvim: nothing to push`.
- Given the push finishes, when the callback runs, then the notification carries dam's own counts,
  `damnit.nvim: todoist: 3 sent, 3 ok, 0 failed`, the window re-renders from a fresh status, and any
  per-mutation failure appears in Notices, because `dam` records a failed mutation as a
  `push_failed` notice (`crates/dam-cli/src/commands/status.rs:144`).

**`p`, pull.**

- Given no operation is running, when `p` is pressed, then `dam pull --json` is queued for every
  remote, or for the remote under the cursor when the cursor is on one.
- Given the pull succeeds, when the callback runs, then the notification is
  `damnit.nvim: todoist: 2 new, 1 updated, 0 conflicts`, from the pull report's own fields, and the
  window re-renders.
- Given the pull is refused because an object has uncommitted local changes, when the callback runs,
  then the message is dam's own (`<oid> changed upstream and has uncommitted local changes; commit or
  reset it, then pull again`), and the window re-renders with the cursor moved to that object in
  Working, so the next key is `-` then `cc`.

**`R`, refresh.**

- Given the window is open, when `R` is pressed, then `dam status --json` runs and the window
  re-renders. The cursor position is preserved by oid, falling back to the same line number, falling
  back to the first section.
- Given an operation is running, when `R` is pressed, then it is queued behind it like anything else.

**Section jumps, `gu`, `gs`, `gp`, `gn`, `gc`.**

- Given the named section exists, when the key is pressed, then the cursor moves to its first entry.
- Given a count is given, when the key is pressed, then the cursor moves to the count-th entry, which
  is what fugitive's jumps do (`fugitive.txt:441` to `457`).
- Given the section is absent, when the key is pressed, then the cursor does not move and the message
  is `damnit.nvim: no Staged section`.

**`co` and `ct`, resolving a conflict.**

- Given the cursor is on a Conflicts line, when `co` is pressed, then
  `dam resolve <oid> --ours --json` is queued; `ct` sends `--theirs`
  (`crates/dam-cli/src/args.rs:215`).
- Given the cursor is anywhere else, when either is pressed, then nothing is sent and the message is
  `damnit.nvim: no conflict on this line`.

The keys are `co` and `ct` rather than `2X` and `3X`, which is fugitive's spelling for the same
choice during a merge conflict (`fugitive.txt:305`). `2X` and `3X` are counts on a key that discards,
and `X` here does not discard a conflict; two plain keys are less to remember and cannot be reached
by a stray count.

**`q` and `g?`.**

- Given the window is open, when `q` or `gq` is pressed, then the window closes and the buffer is
  hidden, not wiped, so a re-open is instant and keeps the folds.
- Given the window is open, when `g?` is pressed, then a floating window shows the key table above,
  keyed to close on any key.

### Folds

One fold per section, using Neovim's own fold machinery with `foldmethod=expr` and a fold expression
that returns `>1` on a heading and `1` elsewhere. Sections start unfolded. Fold state is remembered
by section name for the session, so a re-render does not re-open a section the user closed.

This is a change from `todoist.nvim`, which implements its own folding because it folds a task
subtree rather than a flat section and needs the fold to survive being keyed by task id
(`lua/todoist/list.lua`). A section fold has a stable name and nothing else nested inside it, so the
built-in machinery is enough and `zR`, `zM` and the rest work.

### Highlighting

Every highlight group links to a standard group. No colour is written anywhere in the plugin, so
catppuccin, or any other colourscheme, styles the window with no integration on its side.

| Group | Links to | Used for |
| --- | --- | --- |
| `DamHeader` | `Title` | The four header lines' labels |
| `DamSection` | `Statement` | A section heading |
| `DamOpNew` | `DiffAdd` | The `new` verb |
| `DamOpChanged` | `DiffChange` | The `changed` verb |
| `DamOpRemoved` | `DiffDelete` | The `removed` verb |
| `DamOid` | `Identifier` | The seven-character oid |
| `DamSubject` | `Normal` | The subject |
| `DamPath` | `Directory` | The path |
| `DamLabel` | `Tag` | A label |
| `DamDue` | `Constant` | A due date that is not past |
| `DamOverdue` | `ErrorMsg` | A due date before today |
| `DamPriority1` | `ErrorMsg` | Priority 1 |
| `DamPriority2` | `WarningMsg` | Priority 2 |
| `DamPriority3` | `MoreMsg` | Priority 3 |
| `DamPriority4` | `Comment` | Priority 4, which is dam's lowest |
| `DamRemote` | `Special` | A remote name |
| `DamNotice` | `WarningMsg` | A notice line |
| `DamConflict` | `ErrorMsg` | A conflict line |
| `DamDiffOld` | `DiffDelete` | The old value in an inline diff |
| `DamDiffNew` | `DiffAdd` | The new value in an inline diff |
| `DamRunning` | `MoreMsg` | The `Running` header line |

Priority 1 is the most urgent in `dam`, the opposite of Todoist's scale (dam spec 75). This is the
one place where a hand trained on `todoist.nvim` will be wrong, so the task buffer's header carries
a comment saying so.

Everything but the section headings is applied with extmarks in one namespace, cleared and reapplied
on every render. No syntax file, no regular expressions over the rendered text.

### Icons

`mini.icons` is optional and looked up at render time, never required at load, which is how
`todoist.nvim` treats `fzf-lua` (`README.md`, the picker section). The operator has it installed as
a dependency of `oil.nvim` (`dot_config/nvim/lua/plugins/oil.lua`).

| Thing | Glyph | Fallback |
| --- | --- | --- |
| A task | `mini.icons` `default` for a file | `-` |
| An event | `mini.icons` `default` for a calendar | `@` |
| A remote | `mini.icons` `default` for a git remote | `>` |
| A conflict | `mini.icons` `default` for an error | `!` |

The fallbacks are plain ASCII, one column each, so the rendering is the same width either way and a
terminal with no Nerd Font loses nothing but decoration.

### Window shape

**`:Dam` opens a split, not a float.** `:Dam` opens a horizontal split of the current window,
the way `:Git` opens its summary. `opts.window.float = true` opens a snacks-style centred float
instead, through `Snacks.win` when snacks is loaded and a plain `nvim_open_win` when it is not.

A split is the default because staging is not a glance: the user reads changes, opens task buffers
with `<CR>`, comes back, and commits. A float that closes on focus loss fights all of that, and the
operator's snacks configuration uses floats for pickers and notifications rather than for working
surfaces.

Decided 2026-09-20: a split, the recommended option. Cost to reverse: one option flip. The renderer
does not know which kind of window it is in.

`vim.ui.select` is used for every choice with a fixed set (which remote, ours or theirs when the key
is ambiguous, which path to move to), so the operator's snacks input and picker configuration is what
appears. `vim.ui.input` is used for every free-text prompt. `vim.notify` is used for every outcome,
so noice and the snacks notifier render them.

______________________________________________________________________

## 5. Non-blocking operations

This is the requirement that prompted the plugin's design, so it is specified in full.

### What fugitive does, and why it is not acceptable here

`:Git push` with no bang runs the child through `s:RunWait`
(`vim-fugitive/autoload/fugitive.vim:3635`). That function is a `while` loop over `s:RunTick`, which
is `jobwait([job], 1)` (`:3624`), and inside the loop it calls `getchar()` and forwards every
keystroke to the child (`:3644` to `:3649`). While a push runs, Neovim is not editing: every key you
press goes to git. A slow remote parks the editor for as long as the remote is slow. The doc offers
`:Git!` to run in the background and stream to the preview window (`fugitive.txt:38` to `41`), but
the operator's own mappings are plain `:Git push` and `:Git push --force-with-lease`
(`dot_config/nvim/lua/plugins/git.lua:1444`, `:1445`).

`damnit.nvim` has no equivalent. There is no blocking path, no bang variant that unlocks one, and no
setting that turns blocking on.

### The model

**Every call is a callback.** `vim.system(argv, opts, on_exit)` with `on_exit` given runs
asynchronously and returns immediately (`lua.txt`, `vim.system()`). The plugin never calls `:wait()`.
CI greps `lua/` for `:wait(` and fails on a hit outside `lua/damnit/health.lua`.

**Every callback is scheduled.** `on_exit` runs on the libuv loop. Its whole body is
`vim.schedule(function() ... end)`, and nothing inside it touches a buffer, a window, an option or
`vim.notify` before that. This is the pattern `todoist.nvim` already uses
(`lua/todoist/client.lua:238`, `:251`).

**One queue per store.** `damnit.queue` holds, per store key, a single running entry and a list of
pending ones. An entry is `{ argv, label, on_done, started_at, handle }`.

- Only one `dam` process per store runs at a time. This is what keeps the plugin from being its own
  second SQLite writer, and it is what makes a push and a pull impossible to overlap.
- A read and a write share the queue. There is no fast lane. `dam status` is under 30 ms on ten
  thousand objects (dam spec 386), so a read never delays a write noticeably, and giving reads their
  own lane would reintroduce the concurrent-writer problem the moment a read pulls (section 3).
- Different stores have independent queues, because they are different databases.

**A second network operation is refused, not queued.**

- Given `push todoist` is running, when `P` is pressed again, then nothing is queued and the message
  is `damnit.nvim: push todoist is already running; C-c cancels it`.
- Given `push todoist` is running, when `p` is pressed, then nothing is queued and the message is
  `damnit.nvim: push todoist is running; C-c cancels it, then pull`.

This is the one case where queueing would be wrong. A queued second push is a push the user did not
ask for against a store that has changed since they asked, and it would arrive minutes later with no
one watching. Local operations (`add`, `reset`, `commit`, `status`, `ls`, `show`, `edit`, `new`,
`done`, `mv`, `rm`, `resolve`) queue normally, because each is bounded and each was asked for
explicitly.

**The queue is visible.** The header's `Running` line names the operation and its elapsed time. When
entries are pending it also carries the count: `Running: push todoist  12.3s  (2 queued)`.

### The elapsed timer

One `vim.uv` timer per store, started when an entry begins and stopped when the queue empties.
Interval 250 ms. Its callback is `vim.schedule_wrap`ped, the way `todoist.nvim` wraps its status
poller (`lua/todoist/status.lua:166`).

On each tick it rewrites exactly two things: the `Running` line in the status buffer, if that buffer
exists and is loaded, and the cached statusline string. It does not re-render the window, does not
call `dam`, and does not touch any other buffer. A tick on a store whose window has been closed still
updates the statusline string, which is how a push started from the window and then closed stays
visible.

250 ms is chosen so that the tenths digit of the elapsed time is honest without the redraw being a
cost. At that rate a two-minute push is 480 ticks, each of which is one `nvim_buf_set_lines` on one
line.

### Cancellation

`<C-c>` in the status window, and `:Dam cancel` from anywhere, both cancel the running entry and
discard the pending ones.

The sequence:

1. `handle:kill("sigint")`. `dam` installs a SIGINT handler that sets a cancellation flag
   (`crates/dam-cli/src/main.rs:20`); every wait loop reads it and the process exits 3, which the
   plugin maps to `cancelled`. This is the clean path: `dam` gets to stop its helper and leave the
   store consistent.
1. After a 2000 ms grace, if the process has not exited, `handle:kill("sigterm")`.
1. After a further 2000 ms, `handle:kill("sigkill")`.
1. When the process finally exits, by whatever route, the pending entries are dropped, the timer is
   stopped, the header's `Running` line is removed, and a fresh `dam status --json` is queued so the
   window shows what actually landed.

`SystemObj:kill(signal)` takes a signal name or number (`lua.txt`, `SystemObj:kill()`).

- Given a push is running, when `<C-c>` is pressed, then SIGINT is sent, and on exit the message is
  `damnit.nvim: push todoist cancelled` and the window re-renders.
- Given no operation is running, when `<C-c>` is pressed, then nothing is sent and the message is
  `damnit.nvim: nothing is running`.
- Given a push is running and two reads are queued behind it, when `<C-c>` is pressed, then the two
  reads are discarded and the single status re-read is what runs next.
- Given the process ignores SIGINT and SIGTERM, when four seconds have passed, then SIGKILL is sent
  and the message is `damnit.nvim: push todoist would not stop and was killed`.

Cancelling a push is safe from the store's side: `dam push` records per-mutation results, so a
successful mutation leaves the unpushed set and a failed one stays with its reason
(dam spec 293 to 295). A cancelled push leaves a partially drained unpushed set, which is exactly
what the next `dam status --json` reports, and the next `P` sends what is left.

### Completion

On exit, in `vim.schedule`:

1. The entry is removed from the queue and the next one, if any, is started.
1. `vim.notify` carries the summary `dam` printed, at `INFO` for success and `WARN` for failure.
   The text is built from the report's own fields, never invented: a push says
   `todoist: 3 sent, 3 ok, 0 failed, 0 skipped`, which is `push_line`'s own sentence rebuilt from
   `push_json` (`crates/dam-cli/src/commands/sync.rs:60`, `:75`).
1. `dam status --json` is queued, and the window re-renders from its result.

The window **never patches its own model** from an action's result. A staged object does not move
from Working to Staged because the plugin knows `add` succeeded; it moves because the next `status`
says it is staged. This is the rule `todoist.nvim` already states for its list ("every write is
followed by a read of the view on screen, so what you are looking at came from the server rather than
from a guess at what the write did"), and it is worth more here, where `dam` may have done something
the plugin did not predict, such as rolling a recurring task forward instead of completing it
(`crates/dam-application/src/use_cases/complete.rs`, `Completed::RolledForward`).

### Responsiveness, stated as an invariant

While any `dam` process is running:

- The status buffer stays open and navigable. Motions, searches, folds and `<CR>` all work.
- Every other buffer in the editor is untouched. Typing, LSP, treesitter and autocommands all run.
- No modal prompt is open. The plugin never calls `vim.fn.input`, `vim.fn.confirm`, `getchar` or
  `vim.wait` on an operation's behalf.
- The only thing that changes on screen is the `Running` line and the statusline component.

### Neovim exits mid-push

Nothing special is done, because nothing special is needed.

`vim.system` children are not detached (`detach` is left unset), so a child is killed when Neovim
exits. `dam push` sends mutations to a helper and records each result as it arrives
(dam spec 293 to 295), and the store is SQLite in WAL mode (dam spec 379), so a killed `dam` leaves
the store at whatever the last committed transaction was. The mutations that succeeded are recorded
as pushed; the ones not yet attempted are still unpushed. Nothing is half-written.

What the user sees on the next `:Dam` is a store with a smaller unpushed set than before and no
error, because nothing failed: work simply stopped. This is the same outcome as pressing `<C-c>`.

On `VimLeavePre` the plugin stops its timers and lets the children go. It does not wait for them,
because waiting is the thing this whole section exists to avoid, and a two-minute pull would become
a two-minute quit.

### The test that proves it

`tests/nonblocking_spec.lua`, one case, using the fake `dam` of section 9:

- **Given** a fake `dam` whose `push` subcommand sleeps 3 seconds before printing a valid push
  report, and a `vim.uv` timer at 100 ms that increments a counter,
- **when** the plugin's push is started and the test waits on the completion callback,
- **then** the counter has advanced by at least 25 and at most 35 ticks by the time the callback
  runs, the status buffer was re-rendered afterwards from a fresh `status` call, and the fake's
  recorded argv log shows exactly `push --json` followed by `status --json`.

The tolerance is 25 to 35 rather than exactly 30 because a headless CI runner's timer is not exact
and a tight budget around a real spawn is how a suite starts reddening main on untouched code. The
assertion that matters is that the count is not zero, which is what a blocking implementation would
produce.

A second case proves the refusal: given a push is running, when push is asked for again, then the
fake's argv log holds one `push` and the notification names the running operation.

A third case proves cancellation: given a fake `dam` whose `push` sleeps 10 seconds, when cancel is
called, then the process exits within 3 seconds, the recorded signal is SIGINT, and a `status` call
follows.

______________________________________________________________________

## 6. The task buffer

`:Dam task <oid>`, or `<CR>` on a change in the status window, opens one object as a buffer named
`damnit://task/<oid>`, filetype `damtask`. The layout keeps `todoist.nvim`'s shape: a frontmatter
header of `key: value` lines between two `---` fences, and the body as markdown below them.

```markdown
---
subject: buy oat milk
path: inbox/
priority: 1
due: 2026-09-25
deadline:
labels: errand, home
depends:
recurrence:
---

The kind in the grey carton.

- [ ] check the date
```

An event carries `start`, `end`, `timezone` and `location` instead of `priority`, `due`, `deadline`
and `recurrence`, and its `kind` is shown in a comment line above the fence.

Three differences from `todoist.nvim`'s header:

- `priority` is 1 to 4 with **1 the most urgent** (dam spec 75), the opposite of Todoist's scale.
  The buffer carries `# priority: 1 is highest` as the line above the closing fence so the reversal
  cannot be missed.
- `path` is editable, where `project` and `section` were shown and refused. A changed `path` writes
  through `dam mv`, which carries the object's children with it
  (`crates/dam-application/src/use_cases/subtree.rs`).
- `depends` is a comma-separated list of oids, editable. A cycle is refused by `dam`
  (`Refusal::Cycle`), and the refusal names the chain.

### Writing

`:w` sends only the fields that changed, as one `dam edit` call, then `dam mv` as a second queue
entry when `path` changed. Nothing unchanged is sent, which matters most for `due`: `dam` parses a
due string and a round trip through an unchanged one could move a recurrence
(`crates/dam-application/src/commands/edit.rs` handles `--due` and `--no-due` as exclusive flags,
`crates/dam-cli/src/args.rs:108`).

The field-to-flag map:

| Header field | Set | Cleared |
| --- | --- | --- |
| `subject` | `--subject <text>` | refused, a subject is required |
| `body` | `--body <text>` | `--body ""` |
| `priority` | `-p <1-4>` | refused, a task always has one |
| `due` | `--due <text>` | `--no-due` |
| `deadline` | `--deadline <text>` | `--no-deadline` |
| `labels` | `--label <each added>` | `--unlabel <each removed>` |
| `depends` | `--depends <each added>` | `--undepends <each removed>` |
| `recurrence` | `--recurrence <text>` | `--no-recurrence` |
| `start`, `end` | `--start`, `--end` | refused, an event has both |
| `location` | `--location <text>` | `--no-location` |
| `path` | a second call, `dam mv <oid> <path>` | not applicable |

`labels` and `depends` are sets, so the plugin diffs the buffer's list against the object's list and
sends one `--label` or `--unlabel` per difference in a single call. All of these flags are repeatable
(`crates/dam-cli/src/args.rs:116` to `123`).

`reminders` is **not** in the header, because `dam edit` has no flag that writes it. It is shown in
a comment line, read-only. See **Needed from dam**.

### Validation and diagnostics

Two kinds of refusal, in the two places they belong, which is `todoist.nvim`'s existing split.

The plugin refuses what it can be sure about, before any call, and reports it as diagnostics on the
offending lines in namespace `damnit`:

- A header with no opening or closing fence.
- An unknown field name.
- A repeated field name.
- An empty `subject`.
- A `priority` that is not 1 to 4.
- A `depends` entry that is not at least four hex characters
  (`crates/dam-cli/src/oids.rs:6`).
- A `path` with a segment that is empty.

`dam` refuses everything else, and its refusal is turned into a diagnostic too:

- Given `:w` sends an edit and `dam` exits 2, when the callback runs, then the message is attached as
  an `ERROR` diagnostic on the line of the field the message names, or on line one when it names
  none, and the buffer stays modified.
- Given `:w` sends an edit and `dam` exits 0, when the callback runs, then the buffer is re-rendered
  from the returned object, which `dam edit --json` prints in full
  (measured: `dam edit <oid> --subject "renamed" -p 3 --json` prints the whole wire object), and the
  buffer is marked unmodified.
- Given nothing changed, when `:w` is written, then nothing is sent, the buffer is marked unmodified,
  and the message is `damnit.nvim: nothing changed`.

The buffer stays modified until `dam` answers, so an edit that has not landed still reads as
unwritten and a rejected one leaves the text where it can be fixed. `:q` on an unwritten buffer goes
through Neovim's own `E37` path.

### Subtasks and parents

`dam` models the tree as `path` (dam spec 103 to 111). An object's children are the objects whose
path is nested under its own, which is what `children_of` returns
(`crates/dam-application/src/use_cases/complete.rs`, `plan_complete`).

The task buffer shows a comment line naming the parent path and the count of open children, both
read-only. Re-parenting is `dam mv`, done from the list buffer's `>` and `<` or by editing `path`.

### Completing a parent

This is where `dam` and Todoist differ most, and where the plugin's behaviour has to change.

Todoist closes a task's subtasks with it, server side, and offers no way to close a parent and leave
its subtasks open, which is why `todoist.nvim` asks a yes-or-no question. `dam` does the opposite: it
**refuses**. `dam done X` is refused while any object in `depends` is open or any child of `X` is
open, the refusal lists the blockers, `--force` completes it anyway, and `--force --interactive` asks
what to do with the children and the dependencies (dam spec 134 to 142;
`crates/dam-application/src/use_cases/complete.rs`).

Measured against the built binary:

```
$ dam done 98d8780 --json
{"error": {"kind": "refused", "rule": "blocked",
 "message": "98d8780 cannot be completed:\n  child a9db854 is open\nuse --force to complete it
anyway, or --force --interactive to decide what happens to them",
 "oids": ["98d878013fb0e026d37170e7ceed6707192ae99a",
          "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77"]}}
[exit 4]
```

So the confirm becomes an explanation plus a choice:

- Given `x` or `<CR>`-then-complete is pressed on a task with no open children or dependencies, when
  the call runs, then `dam done <oid> --json` is sent with no prompt.
- Given the task has open children or open dependencies, when `dam done` exits 4 with `rule`
  `blocked`, then the plugin
  reads the blocker lines out of the message, shows them, and offers through `vim.ui.select`:
  `Complete it anyway, keeping the children where they are` and `Cancel`.
- Given the user chooses the first, when the call runs, then `dam done <oid> --force --json` is sent.
- Given `done.interactive = true` is set in dam's config, when `dam done <oid> --force --json` runs,
  then it exits 1 with `a question needs an answer; drop --json/--toon to answer interactively`,
  because `--json` installs a refusing prompt (`crates/dam-cli/src/context.rs:53`,
  `crates/dam-cli/src/prompt.rs:20`) and `done.interactive` turns every `--force` into a question
  (`crates/dam-cli/src/commands/done.rs`). Measured and confirmed. The plugin recognises that exact
  message and says
  `damnit.nvim: dam is configured to ask what happens to the children; run dam done <oid> --force
  --interactive in a terminal`.

The other two dispositions dam offers interactively, moving the children up one level and moving them
into a new group, cannot be reached from the plugin at all in version one. See **Needed from dam**
for the flags that would fix this, which is the single highest-value change on that list.

Completing a recurring task does not complete it: `dam` rolls it forward to the next occurrence and
reports `rolled forward to <date>` (`crates/dam-cli/src/commands/done.rs`). The plugin shows that
wording verbatim rather than saying "done", because the two are different outcomes.

______________________________________________________________________

## 7. Reading, pickers and the rest

### Views

A view is a name and a `dam` query. Two sources, merged, with the plugin's own taking precedence on a
name collision:

1. `opts.views`, a table of name to query string.
1. `dam`'s own saved filters, from config (dam spec 248 to 254), read once per session through
   `dam ls <name> --json`, which resolves a saved filter by name
   (`crates/dam-application/src/use_cases/list.rs`; measured: `dam ls today --json` against a config
   holding `[filter.today]` returned an object list rather than a parse error).

Reading dam's filters means a name declared once in `~/.config/dam/config.toml` works in the editor,
in a terminal and in a herdr pane with no second declaration. A name in neither source is refused
before any call, and the refusal names the declared ones, which is what `todoist.nvim` does today
(`lua/todoist/init.lua`, `M.view`).

The query grammar is dam's, parsed by dam. The terms, from
`crates/dam-domain/src/query/parse.rs`: `done`, `overdue`, `kind:task|event`, `due:`, `deadline:`,
`start:`, `path:`, `label:` or `@name`, `priority:N` or `pN`, `transparency:busy|free`,
`attached:<oid>`, `subject:`, and `<category>:<value>` for any user-declared category. Date values
are `today`, `tomorrow`, `yesterday`, `this-week`, `next-week`, `none`, `before:<date>`,
`after:<date>` or a literal date. Operators are `&`, `|`, `!` and parentheses.

Nothing is parsed locally. A query dam refuses comes back in dam's own wording
(measured: `dam ls 'due:::' --json` gives `dam: due: cannot read "::"`, exit 1).

### The list buffer

Kept as it is, with three changes: the source is `dam ls <query> --json`, the tree is built from
`path` rather than from `parent_id`, and the quick-edit keys map onto `dam` verbs.

| Key | Was | Now |
| --- | --- | --- |
| `<CR>` | open the task buffer | unchanged |
| `R` | re-read the view | unchanged |
| `gd` | jump to the captured code | unchanged, reading `body` instead of `description` |
| `x` | complete | `dam done <oid>`, with section 6's blocker handling |
| `X` | reopen | **blocked**, see **Needed from dam** |
| `dd` | delete, after a confirm | `dam rm <oid>`, after a confirm |
| `p` | cycle the priority | `dam edit <oid> -p <n>`, cycling 4, 3, 2, 1, 4 |
| `s` | set the due date | `dam edit <oid> --due <line>`, the line sent unparsed |
| `l` | toggle a label | `dam edit <oid> --label <x>` or `--unlabel <x>` |
| `m` | move to a project or section | `dam mv <oid> <path>`, the path chosen from the paths in view |
| `a` | add from a Quick Add line | `dam new <subject> --path <current path>`, plus a prompt per field |
| `u` | undo the last complete or reopen | **dropped**, superseded by the working layer |
| `S` | send to the agent | unchanged in shape, see below |
| `za` | fold the subtree | unchanged, the plugin's own folding |
| `>` | make a subtask of the row above | `dam mv <oid> <parent path>/<own segment>` |
| `<` | move out from under the parent | `dam mv <oid> <grandparent path>/<own segment>` |

`a` loses Quick Add syntax because `dam new` takes structured flags and refuses nothing silently
(`crates/dam-cli/src/args.rs:65`). The replacement is one `vim.ui.input` for the subject followed by
`dam new <subject> --path <the path under the cursor>`, and everything else is edited after. A
natural-language line has nothing to parse it here, and a half-parsed one would put the wrong thing
in the store.

`u` goes because the working layer is a better undo than a one-level in-memory stack: a completion
that has not been committed is a working change, visible in the window, and once `dam restore` exists
it is reversible there. Until then, an accidental `x` is reversed by editing `done` back, which also
needs the missing verb. This is a real regression in version one and it is named as one.

Every write is followed by a re-read of the view on screen, unchanged from today.

### Searching

`:Dam pick [<view>]`, fed from `dam ls <query> --json`. `fzf-lua` when it loads, `vim.ui.select`
otherwise, chosen by `opts.picker` with the same three values. `<CR>` opens the task buffer, `<C-x>`
completes through the same path as the list's `x`. With no argument the search follows the screen:
a list buffer's own view, or everything when there is none.

Each line carries the subject, the due date, the priority, the labels and the path, so any of those
can be typed at.

### The completed history

`:Dam done` runs `dam ls done --json` and renders the result, newest first, flat.

The entire paging apparatus of `todoist.nvim` is deleted: no cursor, no fifty-task pages, no
ninety-day windows, no twelve-window walk, no `Reading completed tasks...` state. `dam` holds the
whole history locally and answers a query in under 20 milliseconds on ten thousand objects
(dam spec 385). One call, one render.

`R` re-reads. `u` (reopen) is blocked, for the missing verb.

### Capture from code

`:Dam capture`, with or without a range, unchanged in behaviour. The task is created with:

```
dam new "<content>" --path inbox/ --body "<repo> <path>:<line>" --json
```

The location text is the same format `todoist.nvim` writes today, `damnit.nvim
lua/damnit/status.lua:112`: the repository name, then the path inside it, then the line. It is
relative and never absolute, because a body is text that syncs to a remote and onto a phone.

`gd` in the list parses the same format out of `body` and follows it, with the same four
unfollowable cases reported as messages rather than errors.

### Sending a task to the agent

`S` in the list buffer, unchanged in shape. The brief's fields change, because dam's are different
and because a dam object has no URL: it is local.

```text
dam task: file taxes
oid: 78b8950
store: ~/.local/share/dam/dam.db
path: home/finances/
due: 2026-09-20
priority: p1
labels: home, slow

receipts are in the drawer

note: start with the receipts
```

A field the object has nothing for is left out rather than written empty. `oid` is the seven-character
prefix, which is what an agent would type at `dam show`.

The delivery path is unchanged: inside herdr, `herdr pane send-text` as one bracketed paste, then
`herdr agent focus`, with the agent pane chosen from `herdr agent list` as a pane herdr names an
agent for, in this workspace, other than this one. Outside herdr, or on any of the four failures, the
same text goes to the unnamed register and `+`.

**The hand-off record is dropped.** `todoist.nvim` writes a comment on the task recording the
hand-off. `dam` has no comments: they are out of scope for dam version one (dam spec 435). Every
notification therefore ends `no hand-off record written`, which is the same sentence the clipboard
path already uses, so the two cannot be confused and neither pretends a record exists.

### The herdr pane parity clause

Kept, verbatim in spirit. `herdr-damnit` is the herdr client, its own repository and its own
specification (dam spec 44). It will declare its views as `[[views]]` entries with a `name` and a
`filter`; this plugin declares them as the keys and values of `opts.views`. Keeping them equal is a
convention rather than a mechanism, because neither reads the other's configuration.

What is new is that both can now defer to a third source: a saved filter in
`~/.config/dam/config.toml` is read by `dam` itself, so a name declared there needs no entry in
either client. That is the parity clause's own goal reached by a better road, and the recommendation
is that the operator declare views there and leave `opts.views` empty.

### The sidebar

Unchanged. A fixed-width vertical split on one edge of the tabpage holding one view, `winfixwidth`,
`winfixheight` and `winfixbuf`, the `WinNew` and `WinResized` autocommands that restore the width
when the sidebar is briefly the only window, per tabpage, and a window-local flag as the only thing
remembered about it.

`opts.sidebar.view` names a view, refused before the split is made when the name is not declared.

### The statusline

`require("damnit").status()` keeps its contract exactly: it is called on every redraw, does no work,
and returns the string the last background fetch built. `3 due, 1 overdue`, or one half of that, or
an empty string, or `dam !` when the last fetch failed.

The fetch is `dam ls "!done & (due:today | overdue)" --no-pull --json` (task 25 ruling, which
supersedes the `dam ls "due:today | overdue" --json` this line first named: `due:today` matches a
completed task as readily as an open one), on a `vim.uv` timer every `opts.refresh_interval`
seconds, default 60, started by the first call to `status()` or by turning reminders on. One poller,
and both features read the objects it stored, unchanged.

Two additions:

- While an operation is running, `status()` returns the operation and its elapsed time instead of the
  count: `dam: push 12.3s`. A push in flight is more worth a statusline slot than a count that has
  not changed, and it is how the user sees a push started from a window they then closed.
- `dam !` replaces a stale count on failure, unchanged from today, because a count left standing
  after the tool stopped answering is worse than no count.

A task due today at 09:00 is overdue from 09:00 on. A task due today with no time is due for the
whole of its day and overdue only once the day is over. `dam`'s `due` is a date or a datetime with a
timezone (dam spec 76), and the wire form is the text of either, so the plugin tells them apart by
whether the string carries a time.

### Due reminders

`opts.reminders`, off by default. With it on, a task carrying a time raises one `vim.notify` when its
time has come, once per task per due instant, keyed `<oid>@<stamp>` so a recurring task's next
occurrence and a task moved to a new time are both announced again. A full-day task never raises one.

It rides on the statusline's fetch, so there is one poller. The lateness is `refresh_interval` at
worst. The first fetch after the timer starts records what is already overdue and says nothing, so
opening the editor in the evening does not replay the morning. The timer stops on `VimLeavePre`.

**No network call is made by the plugin.** The poll is `dam ls`, a local SQLite query. The one
qualification, stated in section 3, is that a remote with `stale` set in dam's config makes `dam ls`
pull that remote first (dam spec 372). **Superseded for this poll by dam 0.2.0 (task 25 ruling):**
`--no-pull` shipped as a global flag and the poll passes it, so the poll is guaranteed local and the
qualification survives only for the reads that do not pass it.

### `:checkhealth damnit`

| Check | Reports |
| --- | --- |
| `dam` on `PATH` | ok with the resolved path, or an error with the install line |
| `dam --version` | ok with the version and the supported range, or an error naming the mismatch |
| The store | ok with the resolved path and the object count from `dam ls --json`, or an error |
| The config | ok with the resolved path, or a warning that dam is using its default |
| Remotes | one line per remote: name, url, path narrowing, stale setting |
| Credential sources | superseded, see section 3: dam reports no credential to warn from |
| Conflicts | a warning with the count when `dam status --json` reports any |
| Views | ok with the declared names, from both sources, and an error naming any that `dam ls` refuses |

It reports nothing about any credential's value, because it never sees one: the plugin holds no token
and reads no config file.

Like the current health check, it runs its `dam` calls inside `vim.wait`, which keeps the event loop
turning so the `vim.system` callbacks can run, and it is the one place in the plugin where waiting is
correct (`lua/todoist/health.lua:19`).

______________________________________________________________________

## 8. Architecture

### Modules by role

Each has one responsibility and one reason to change.

| Module | Responsibility |
| --- | --- |
| `damnit` | Options, `setup`, and the six functions a keymap calls. Nothing else. |
| `damnit.dam` | The only module that spawns a process. argv, JSON, errors, the handshake. |
| `damnit.queue` | The per-store operation queue, the elapsed timer, cancellation. Calls `damnit.dam`. |
| `damnit.status_model` | One status document into the window's model. Pure, no Neovim API. |
| `damnit.render` | A model into lines, extmarks and folds. Knows nothing about `dam`. |
| `damnit.window` | Creating, finding and focusing the status window and its buffer. Split or float. |
| `damnit.keys` | Every mapping in every buffer this plugin owns, in one table per filetype. |
| `damnit.actions` | What each key does: read the cursor, queue the call, handle the result. |
| `damnit.commit_buffer` | The commit message buffer and its write. |
| `damnit.task_buffer` | One object as a buffer: render, parse, validate, diagnose, write. |
| `damnit.task_format` | The frontmatter format, both directions. Pure. |
| `damnit.list` | The list buffer: render, keys, quick edits. |
| `damnit.list_format` | The list's lines and its tree layout. Pure. |
| `damnit.tree` | Building a tree from `path`. Pure. |
| `damnit.picker` | The search, and the fzf-lua or `vim.ui.select` choice. |
| `damnit.sidebar` | The fixed-width split. |
| `damnit.poll` | The statusline string, the reminders, and the one timer behind both. |
| `damnit.capture` | Capture from code, and the location text. |
| `damnit.location` | Parsing a location out of a body and following it. Pure. |
| `damnit.send` | The agent brief and its delivery. |
| `damnit.views` | Resolving a view name against `opts.views` and dam's filters. |
| `damnit.health` | `:checkhealth damnit`. |

### Dependency direction

```
        keys ─┐
              ├─> actions ──> queue ──> dam ──> (vim.system)
    window ───┤                │
    render ───┘                └─> status_model (pure)
       │
       └─> (buffer, extmarks, folds)
```

Three rules, each of which CI can check:

1. **Only `damnit.dam` calls `vim.system`.** Grep `lua/` for `vim.system` and assert one file.
1. **The pure modules call no `vim.*` API.** `status_model`, `task_format`, `list_format`, `tree`,
   `location` and `answer` are grepped for `vim.api`, `vim.fn`, `vim.system`, `vim.notify` and
   `vim.schedule`. They may use `vim.tbl_*`, `vim.islist`, `vim.json` and `vim.split`, which are data
   functions.
1. **`render` does not know `dam` exists.** It takes a model and a buffer.

The pure layer is what makes the window testable without a window: a golden render test builds a
model from a JSON fixture, renders into a scratch buffer, and compares the lines.

### File size

Every file targets 300 lines and none exceeds 500, comments and inline tests included. This is the
standing rule for Rust in the dotfiles repository and it applies here for the same reason: a file
that has to be read whole to be changed safely is the limit.

The two files most at risk are `actions` and `render`. `actions` splits by section when it grows:
`actions/stage.lua`, `actions/commit.lua`, `actions/sync.lua`. `render` splits into `render.lua` and
`render/diff.lua` for the inline field diff. Neither split is made in advance.

### What is deleted

`lua/todoist/client.lua` (478 lines) and `lua/todoist/token.lua` (123 lines) go entirely, along with
their specs. `lua/todoist/completed_history.lua` (219 lines) goes, because the paging it implements
has nothing to page. That is roughly 820 lines of the current 3,600 removed rather than ported, and
the two hardest parts of the plugin to test go with them.

______________________________________________________________________

## 9. Testing

### The harness

Unchanged: `nvim --headless --clean -l tests/run.lua [<name>_spec]`. A spec returns a table of
`["what it does"] = function() ... end` cases and asserts with plain `assert`. No plenary, no busted.
A spec with no cases is an error, so gutting one cannot leave the run green. The runner is 74 lines
and stays as it is.

The current suite is 259 cases in 2.93 seconds, measured on 2026-09-20. The replacement suite has a
budget of 5 seconds, most of which is the three timing cases in `nonblocking_spec.lua`.

### The fake dam

A single shell script written into a temporary directory that the spec puts at the front of `PATH`.
It replaces the fake `vim.system` pattern the current suite uses for curl, and it is better, because
it exercises the real spawn, the real argv, the real exit code and the real stderr.

```sh
#!/bin/sh
# Records its argv, then replays a fixture chosen by the first argument.
printf '%s\n' "$*" >> "$DAMNIT_TEST_LOG"
case "$1" in
  --version) echo "dam ${DAMNIT_TEST_VERSION:-0.2.0}"; exit 0 ;;
esac
if [ -n "$DAMNIT_TEST_SLEEP" ]; then sleep "$DAMNIT_TEST_SLEEP"; fi
if [ -n "$DAMNIT_TEST_STDERR" ]; then echo "$DAMNIT_TEST_STDERR" >&2; fi
if [ -n "$DAMNIT_TEST_EXIT" ] && [ "$DAMNIT_TEST_EXIT" != 0 ]; then exit "$DAMNIT_TEST_EXIT"; fi
cat "$DAMNIT_TEST_FIXTURES/$1.json"
```

Four environment variables drive every case: which fixture directory, how long to sleep, what to
write on standard error, and what to exit with. The argv log is what every assertion about "what the
plugin sent" reads.

The fixtures are the plugin's own, under `tests/fixtures/`, one JSON file per subcommand per
scenario, each captured from the real `dam` against a scratch store and committed. They are checked
against the real binary by hand whenever dam's version moves, and the version handshake is what makes
a drift visible.

Nothing in the suite reaches the network. Nothing runs the real `dam`. Nothing touches
`~/.local/share/dam/`. The fake's directory is removed at the end of each spec.

### The cases

- **`dam_spec`.** argv construction per verb, `--store` passthrough, JSON decoding, and the `pcall`
  around a missing binary.
- **`answer_spec`.** One finished process read directly: the error table for exits 1, 2, 3, 4 and
  124, a document whose `rule` or `oids` arrive in a shape dam does not send, a document with no
  message of its own, and a call a signal killed.
- **`handshake_spec`.** The supported range accepts 0.2.0 and refuses 0.3.0, an unparseable banner
  warns and proceeds, an absent `dam` refuses.
- **`status_model_spec`.** One fixture per section, an empty status, a status with every section
  populated, and the field-diff computation against every field `changed_fields` names.
- **`render_spec`.** A golden render per window state: empty, working only, staged only, both, with
  an unpushed remote, with notices, with conflicts, with an inline diff open, and with `Running` in
  the header. Nine golden files under `tests/golden/`.
- **`nonblocking_spec`.** The three timing cases of section 5.
- **`queue_spec`.** One entry at a time per store, a second push refused, local calls queued, two
  stores independent, and cancellation dropping the pending entries.
- **`keys_spec`.** Every key in the table of section 4, each asserting the argv the fake recorded.
- **`task_format_spec`.** The frontmatter both directions, every field, the priority reversal, and
  an event's fields.
- **`task_buffer_spec`.** Only changed fields sent, `--no-due` on a cleared due, the label and
  depends set diff, `dam mv` as a second call on a changed path, and diagnostics from both a local
  refusal and a dam refusal.
- **`done_spec`.** The blocker path: exit 4 with `rule` `blocked` shows the blockers dam named in
  `oids`, the choice sends `--force`, the
  `done.interactive` message is recognised, and a rolled-forward result is reported as rolled
  forward rather than as done.
- **`views_spec`.** `opts.views` wins over a dam filter, an undeclared name is refused before any
  call, and a refused query is reported in dam's wording.
- **`list_spec`, `list_format_spec`, `tree_spec`.** Ported from the current suite, retargeted at
  `path`.
- **`picker_spec`, `sidebar_spec`, `capture_spec`, `location_spec`, `send_spec`.** Ported,
  retargeted at dam's fields.
- **`poll_spec`.** The statusline string, the running-operation override, `dam !` on failure, the
  reminder key, and the silence on the first fetch.

A golden render is a file of expected lines plus the expected extmark list as a table, compared
whole. A one-character change to a rendering is a diff a reviewer can read, which is the point of
keeping them as files.

### CI

Unchanged: `.github/workflows/ci.yml` as it stands, a lint job running `stylua --check` and
`luacheck` on pinned versions, and a test job running the harness on a pinned Neovim, currently
v0.12.5, with both downloads checksum verified.

Three greps are added to the lint job, each a one-line `grep` that must find nothing:

1. `vim.system` outside `lua/damnit/dam.lua`.
1. `:wait(` outside `lua/damnit/health.lua` and `tests/`.
1. `vim.api`, `vim.fn` or `vim.notify` in the six pure modules.

______________________________________________________________________

## 10. Performance, errors, scope and decisions

### Performance targets

| Measurement | Target |
| --- | --- |
| `:Dam` to a drawn window, on a store of 2,000 tasks | under 100 ms |
| The `dam status --json` call inside that | under 30 ms, dam's own target (dam spec 386) |
| Decoding and modelling that document | under 20 ms |
| Rendering lines, extmarks and folds | under 30 ms |
| A re-render after a write | under 100 ms, the same path |
| The elapsed-timer tick | under 1 ms, one `nvim_buf_set_lines` on one line |
| `status()` on a redraw | under 0.05 ms, a table lookup |

All of these are measured with `vim.uv.hrtime` around the phase, printed by a spec that runs against
a generated 2,000-object fixture, and reported as the median of eleven runs. The spec **warns** when
a phase exceeds its target and does not fail: a timing assertion against a real spawn on a shared CI
runner reddens main on untouched code, and a warning that names the phase is what a human acts on.

`dam` call latency is measured separately and recorded, not asserted: the plugin cannot make `dam`
faster, and a regression there belongs to dam's own suite.

### Message wording

One sentence. What happened, then what to do about it, separated by a semicolon when both are
needed. Every message is prefixed `damnit.nvim: ` when the plugin wrote it, and carries `dam`'s own
wording unprefixed when `dam` wrote it, so the two are never confused.

Levels: `INFO` for an outcome the user asked for, `WARN` for a refusal or a failure they can act on,
`ERROR` only for a configuration problem that makes the plugin unusable. Never `DEBUG`, and no
logging to a file.

Good:

```
damnit.nvim: push todoist is already running; C-c cancels it
damnit.nvim: dam has no verb that restores a committed object; commit the change or edit it back
damnit.nvim: todoist: 3 sent, 3 ok, 0 failed, 0 skipped
```

Bad, and why:

```
damnit.nvim: Error!                          says nothing
damnit.nvim: failed to execute dam push       names the mechanism, not the problem
damnit.nvim: could not stage (see :messages)  the message is the message
```

No message ever contains a credential, a path outside the store's own, or a full oid, which is forty
characters of noise where seven identify it.

### Out of scope for version one

- Events. `dam` models them fully (dam spec 80 to 101) and the plugin renders them read-only in a
  list and in the task buffer, but there is no calendar view, no agenda, and no `--event` creation
  path. `:Dam capture` and `a` make tasks.
- `dam log` as a browsable history. The Unpushed section shows commits and `<CR>` opens one. There is
  no log buffer, no commit graph and no `dam show <commit>` navigation beyond that.
- Editing `reminders` or `recurrence` through anything but the raw header field, because `dam edit`
  takes recurrence as an opaque string and takes no reminder flag at all.
- Staging part of a change. Fugitive stages a hunk (`fugitive.txt:290`); a `dam` change is an object,
  and there is no sub-object unit to stage.
- `--toon` output. It exists for language models reading lists (dam spec 234 to 237) and the plugin
  reads JSON.
- A second store open at once. The design admits it (one buffer and one queue per store key) and
  nothing in version one opens a second.
- Attendees, conferences and attachments on an event: shown, never edited.
- Any daemon, socket or long-lived `dam`. One process per call, which is dam's own model for
  version one (dam spec 388 to 390).

### Decisions

Each decided 2026-09-20 on the recommended option, with what it costs to reverse.

1. **The status window opens as a split, not a float.** `opts.window.float` opens the other.
   Decided 2026-09-20: a split, the recommended option. Cost to reverse: one option flip; the
   renderer does not know the difference.
1. **`p` pulls, and `gP` stays unbound.** Decided 2026-09-20: `p` for pull, the recommended option.
   Cost to reverse: a fugitive hand presses `p` expecting a preview and starts a network operation.
   Mitigated by the operation being cancellable with `<C-c>` and by `Running` appearing in the header
   immediately.
1. **`cc` opens a message buffer, not `vim.ui.input`**, because a commit message is worth more than
   one line and `vim.ui.input` gives one. Decided 2026-09-20: the message buffer, the recommended
   option. Cost to reverse: a two-word commit costs a `:w`. An `opts.commit.prompt = true` would
   switch it, and is not built.
1. **dam's saved filters are read, with `opts.views` winning a collision.** Decided 2026-09-20: read
   them, the recommended option. Cost to reverse: one extra `dam ls` per unknown name, and a name
   that resolves differently in the editor than in a terminal when the operator declares it in both
   places with different queries.
1. **No shim for `:Todoist`.** Decided 2026-09-20: none, the recommended option. Cost stated in
   section 2: one editing session.
1. **The hand-off record is dropped.** The alternative is appending a line to the object's `body`
   through `dam edit --body`, which works but turns every hand-off into an unstaged working change
   the operator has to stage and commit. Decided 2026-09-20: drop it, the recommended option. Cost to
   reverse: an agent hand-off leaves no trace in the store, only in the notification.
1. **The supported dam range is `>=0.2.0 <0.3.0`** while dam is pre-1.0, widened by hand on each dam
   minor whose JSON shapes are unchanged. Decided 2026-09-20: this range, the recommended option,
   moved off `>=0.1.0 <0.2.0` the same day when dam 0.2.0 replaced the error prose with a document.
   Cost to reverse: a dam minor release refuses to work with the plugin until one constant moves.
1. **Health warns on `_command` credentials.** Decided 2026-09-20: warn, the recommended option. Cost
   to reverse: a noisy health report on a machine whose credential command is non-interactive, such
   as a keychain read. The warning names the interactive case explicitly so it reads as information
   rather than as a fault.
1. **`X` blocks on updates rather than reconstructing the old value with `dam edit` flags.**
   Reconstructing it would mean reimplementing a dam verb in Lua, incompletely: `reminders` has no
   edit flag, `labels` and `depends` are sets that need a diff, and a partial restore that looks
   complete is worse than a refusal. Decided 2026-09-20: block, the recommended option. Cost to
   reverse: `X` is useful on one of three change kinds until `dam restore` ships.
1. **The 2,000-object performance target warns rather than fails**, for the CI-flake reason stated
   above. Decided 2026-09-20: warn, the recommended option. Cost to reverse: a performance regression
   ships and is caught by a human reading the warning rather than by a red build.

______________________________________________________________________

## Needed from dam

Seven changes to `dam`, each one something the window needs and none of which the plugin should
implement on its own. They are ordered by what they block.

### 1. Non-interactive completion dispositions

**Blocks:** completing any parent that has open children, from any client, whenever
`done.interactive = true`.

`dam done <oid> --force --interactive` asks the operator what happens to the open children and the
open dependencies, through a terminal prompt (`crates/dam-cli/src/commands/done.rs`, `ask`). Under
`--json` the prompt is replaced by one that refuses (`crates/dam-cli/src/context.rs:53`), so the
call fails. Worse, `done.interactive = true` in config turns a plain `--force` into the same
question, so a client cannot force a completion at all on such a machine. Measured:

```
$ dam done 98d8780 --force --json          # with done.interactive = true
dam: a question needs an answer; drop --json/--toon to answer interactively
[exit 1]
```

**Proposed change:** two flags on `done` that express what the prompt asks, so a client can answer it
without a terminal.

```
dam done <oid> --force --children up|keep|into:<name> --depends drop|keep
```

Each corresponds exactly to a variant of `ChildDisposition` and `DependencyDisposition`
(`crates/dam-domain/src/completion.rs`). When either flag is given, the prompt is not asked, whatever
`done.interactive` says. When `--force` is given with neither flag and `done.interactive` is set, the
current behaviour is unchanged.

### 2. A verb that restores a committed object

**Blocks:** `X` in the status window for a change whose op is `update` or `delete`, and any undo of
an accidental `x` or `dd`.

There is no `restore`, no `checkout` and no `reset --hard` anywhere in the workspace. A working
change can be staged, unstaged and committed, but it cannot be thrown away.

**Proposed change:** `dam restore <oid>...` and `dam restore -A`, which set the working layer of the
named objects back to the last commit, refusing on an object that has no committed state and
suggesting `dam rm` for it. The name follows git's own modern spelling and the tool's stated rule of
using git's word where git has one (dam spec 32).

### 3. A verb that reopens a completed task

**Blocks:** `X` in the list buffer, `u` in the completed history, and editing `done` in the task
buffer.

`dam done` sets `done` to true. `dam edit` has no `--done` or `--undone` flag
(`crates/dam-cli/src/args.rs:96` to `140`), and no other verb sets it back. A task completed by
mistake stays completed.

**Proposed change:** `--done` and `--undone` as a mutually exclusive pair on `dam edit`, which is
where every other field already lives.

### 4. A machine-readable error: arrived in dam 0.2.0

**Was blocking:** every error path in the plugin acting on anything but an exit code, and the three
substring matches section 3 used to carry.

**Delivered** by dam 0.2.0 (`webdavis/damnit` PR #4), in a shape of its own rather than the one
proposed here: the document goes on standard error rather than standard output, its keys are
`kind`, `rule`, `message` and `oids` rather than `code`, `oid` and `blockers`, and a rule refusal
exits 4 rather than 2. Section 3 carries the delivered contract, and the substring table is gone.

### 5. `fields` in a change document: arrived in dam 0.2.0

**Was blocking:** nothing, but it made the window's field summary a copy of dam's logic rather than
a read of dam's answer.

**Delivered** by dam 0.2.0 (`webdavis/damnit` PR #4): a change document carries
`"fields": ["subject", "due"]`, an update names what moved, a create names every field the new
object carries beyond its defaults, and a delete names none. The same release makes `status --json`
answer rows without their embedded objects unless `--full` is passed, and writes the object's own
columns flat on the row instead. Section 3's shape block above is the one to read for the row.

The window draws the field summary for an update only, which is what `dam status`'s own human form
does: its `new` and `removed` lines carry no parenthetical even though those rows name fields.

### 6. `--no-pull`

**Blocks:** nothing, but it is what lets a background poll promise to be local.

`dam ls` and `dam show` call `maybe_pull_stale` before answering
(`crates/dam-cli/src/commands/ls.rs`), so a remote with `stale` set makes a read reach the network.
A client polling every 60 seconds for a statusline count cannot say whether it is making network
calls.

**Proposed change:** a global `--no-pull` flag that skips `maybe_pull_stale` for that invocation. It
changes no default and no configuration; it lets a caller say "answer from what you have".

### 7. Last-pull times in `remote list`

**Blocks:** the window header saying anything about freshness.

`dam remote list --json` reports name, helper, url, path and `stale_seconds`
(`crates/dam-cli/src/commands/remote.rs`, `remote_json`). The store knows when each remote was last
pulled, because `maybe_pull_stale` reads it (`store.last_pull`), but nothing prints it.

**Proposed change:** add `"last_pull": "<timestamp or null>"` to each entry, so the header can say
`todoist (1 unpushed, pulled 4m ago)` instead of just a count.

______________________________________________________________________

## Decisions recorded

Made in the design conversation on 2026-09-20.

- The plugin is renamed `damnit.nvim`, the repository is renamed in place on GitHub, and the command
  family is `:Dam`. No compatibility shim.
- The token and every credential leave the plugin entirely. There is no option that holds one, names
  one, or reads one.
- `dam` is reached only through its command line, with `--json`, through `vim.system` with a
  callback. `:wait()` is forbidden outside the health check and the tests, and CI greps for it.
- `vim.system` is called in exactly one module. The five modelling and formatting modules call no
  Neovim API at all, which is what makes the window testable headless.
- The status window is the plugin's default surface, a split, modelled on fugitive's summary buffer,
  with fugitive's keys wherever the meaning carries over and no key reused where it does not.
- Four fugitive sections have no counterpart and are not invented: Untracked, Rebasing, Reverting and
  Unpulled. Unpulled becomes Notices, which is what `dam pull` actually leaves behind.
- The window is unmodifiable and the inline field diff is drawn with extmark virtual lines, where
  fugitive inserts text into a modifiable buffer.
- The window never patches its own model. Every action is followed by a fresh `dam status --json`.
- One operation per store at a time, in a queue. A second network operation is refused with a message
  rather than queued silently; local operations queue.
- Cancellation is SIGINT first, because `dam` handles it and exits 3, then SIGTERM, then SIGKILL,
  with two seconds between each.
- Every highlight group links to a standard group. No colour is written in the plugin.
- Priority 1 is the most urgent, which is the reverse of Todoist's scale, and the task buffer says so
  in a comment line rather than translating it.
- The Todoist filter language goes; dam's query grammar replaces it, parsed by dam, and dam's own
  saved filters are read alongside `opts.views`.
- The completed history loses its paging entirely, because a local query has nothing to page.
- The agent hand-off is kept and its record is dropped, because dam has no comments.
- The session undo (`u`) is dropped in favour of the working layer, and this is a real regression
  until `dam restore` ships.
- `X` ships for a `create` only, through `dam rm`, and refuses on an `update` or a `delete` rather
  than reconstructing the old value field by field in Lua.
- Where the window needs something `dam` does not have, it is listed in **Needed from dam** with the
  proposed dam change, and the plugin does the reduced thing in the meantime and says so.
