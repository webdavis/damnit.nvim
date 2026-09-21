# damnit.nvim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `todoist.nvim` into `damnit.nvim` in place: a Neovim client of the `dam` task store whose
default surface is a fugitive-style staging window, whose every `dam` call is non-blocking, and which
holds no credential of any kind.

**Architecture:** One module spawns processes (`damnit.dam`). One queue serialises them, one entry per
store at a time (`damnit.queue`). Five modules are pure and call no Neovim API, which is what makes the
window testable headless. The status window re-renders in full from a fresh `dam status --json` after
every action and never patches its own model.

**Tech Stack:** Lua 5.1 (LuaJIT) for Neovim 0.12.5. `vim.system` with callbacks, `vim.json`, extmarks,
`vim.uv` timers. Tests run headless under `nvim --headless --clean -l tests/run.lua [<name>_spec]`
against a fake `dam` shell script placed at the front of `PATH`. Lint is stylua 2.5.2 and luacheck.

**Spec:** `docs/superpowers/specs/2026-09-20-damnit-nvim-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

Carried verbatim from the brief:

- Lua tests run headless the way the repository's existing tests do and every test passes in under a
  second.
- No em-dashes anywhere.
- Comments say what the code does or why, never what was rejected.
- Conventional commits with `SKIP_AI_COMMIT=1` and no co-author trailer.
- The plugin never holds or reads a Todoist token (dam does).
- Every `dam` call is non-blocking (`vim.system` with a callback) except reads the spec names as
  synchronous.
- Public repository, so no home paths, machine names or tokens in code, tests, fixtures or docs.

From the spec, and equally binding:

- `--json` on every `dam` call, without exception, including the ones whose result is discarded.
- Only `lua/damnit/dam.lua` calls `vim.system`. CI greps for it.
- `:wait(` appears nowhere outside `lua/damnit/health.lua` and `tests/`. CI greps for it.
- The pure modules `status_model`, `task_format`, `list_format`, `tree`, `location` and `answer`
  call no `vim.api`, `vim.fn`, `vim.system`, `vim.notify` or `vim.schedule`. They may use `vim.tbl_*`,
  `vim.deep_equal`, `vim.json`, `vim.trim` and `vim.split`, which are data functions. CI greps for it.
- Every result is marshalled through `vim.schedule` before it touches a buffer, a window or an option.
- Every file targets 300 lines and none exceeds 500, comments included.
- Every highlight group links to a standard group. No colour is written anywhere in the plugin.
- A message the plugin wrote is prefixed `damnit.nvim: `. A message `dam` wrote is carried verbatim and
  unprefixed, so the two are never confused.
- No message contains a credential, a path outside the store's own, or a full forty-character oid.
  Seven characters identify one.
- The supported dam range is `>=0.2.0 <0.3.0`.
- Priority 1 is the most urgent, the reverse of Todoist's scale.
- `stylua --check .` and `luacheck .` pass. Both are what CI runs.

## The one place this plan departs from the spec, and why

Spec section 5 sizes its three timing cases at a 3 second sleep with a 25 to 35 tick band, and section 9
gives the suite a 5 second budget. The brief's constraint is that every test passes in under a second.
The plan resolves this in favour of the brief: the fake `dam` sleeps 400 ms, the observer timer ticks
every 20 ms, and the assertion is a floor (at least 5 ticks) rather than a band. The floor is what
actually distinguishes a non-blocking implementation from a blocking one, which produces zero ticks, and
a floor cannot redden the build on a slow runner the way a ceiling can. The queue's own grace periods
are module constants a spec lowers, so the cancellation ladder is exercised in tens of milliseconds
rather than in seconds.

## File structure

Created under `lua/damnit/`:

| File | Responsibility |
| --- | --- |
| `init.lua` | Options, `setup`, and the functions a keymap calls. Nothing else. |
| `message.lua` | The `damnit.nvim: ` prefix rule, in one place. |
| `dam.lua` | The only module that spawns a process: argv, the handshake, the call. |
| `answer.lua` | One finished process into a result or an error: exit code, signal, document. Pure. |
| `queue.lua` | The per-store queue, the elapsed timer, cancellation. |
| `status_model.lua` | One status document into the window's model. Pure. |
| `render.lua` | A model into lines and extmark specs. `render.lines` is pure. |
| `window.lua` | Creating, finding and focusing the status window and its buffer. |
| `keys.lua` | Every mapping in every buffer this plugin owns, one table per filetype. |
| `actions.lua` | What each key does: read the cursor, queue the call, handle the result. |
| `commit_buffer.lua` | The commit message buffer and its write. |
| `task_buffer.lua` | One object as a buffer: render, parse, validate, diagnose, write. |
| `task_format.lua` | The frontmatter format, both directions. Pure. |
| `list.lua` | The list buffer and the completed history: render and keys. |
| `quick_edit.lua` | The list's quick edits, split out under the 300 line rule. |
| `list_format.lua` | The list's lines and its tree layout. Pure. |
| `tree.lua` | Building a tree from `path`. Pure. |
| `due.lua` | Telling a due date from a due datetime, and which are overdue. |
| `picker.lua` | The search, and the fzf-lua or `vim.ui.select` choice. |
| `sidebar.lua` | The fixed-width split. |
| `poll.lua` | The statusline string, the reminders, and the one timer behind both. |
| `capture.lua` | Capture from code, and the location text. |
| `location.lua` | Parsing a location out of a body. Pure. |
| `location_edit.lua` | Reading a location off the buffer, and opening the file one names. |
| `send.lua` | The agent brief and its delivery. |
| `views.lua` | Resolving a view name against `opts.views` and dam's filters. |
| `health.lua` | `:checkhealth damnit`. |

Deleted outright: `client.lua` (478 lines), `token.lua` (123), `completed_history.lua` (219) and
`completed.lua` (236), with their specs and the three loopback specs that drive an HTTP server.

Test files created: `tests/helpers/fake_dam.lua`, `tests/fixtures/**.json`, `tests/golden/**.lua`, and
one spec per module as section 9 of the spec names them.

## Task order and the dam dependency

Tasks 1 to 28 depend on `dam 0.2.0` as built and are ordered first. Tasks 29 to 36 each wait on one
change in `webdavis/damnit`, and each names it. PR B landed on 2026-09-20 as dam 0.2.0, so the three
tasks that named it are unblocked and their text carries the delivered shape rather than the
proposed one:

| Task | Waits on |
| --- | --- |
| 29 | dam PR A: `dam edit --undone` |
| 30 | dam PR A: `dam restore` |
| 31 | dam PR A: `dam done --children/--depends` |
| 32 | dam PR B, landed: the error document on standard error, exit 4 for refusals only |
| 33 | dam PR B, landed: `fields` in change documents |
| 34 | dam PR B, landed: `status` without embedded objects |
| 35 | dam PR C: `--no-pull`, and last-pull times in `remote list` |
| 36 | dam PR D: the saved-filters command and the category catalogue |

## Not in this plan

Two pieces of the design live outside this repository and are not tasks here.

The lazy.nvim spec and the which-key label in the operator's dotfiles
(`dot_config/nvim/lua/plugins/todoist.lua` becoming `damnit.lua`) are a change to that repository. Section
2 of the design carries the file to write, and Task 28 puts the same spec in this repository's README so
the two cannot drift silently.

The GitHub rename of `webdavis/todoist.nvim` to `webdavis/damnit.nvim` is already done. Nothing in these
tasks depends on it beyond the module names Task 1 writes.

---

### Task 1: Rename the tree in place

Mechanical only. Every identifier, file path and command name changes; no behaviour does. The suite is
green before and after with the same case count, which is the whole point of doing this first.

**Files:**

- Rename: `lua/todoist/` to `lua/damnit/` (19 files), `plugin/todoist.lua` to `plugin/damnit.lua`
- Modify: every `*.lua` under `lua/`, `plugin/` and `tests/`, and `README.md`
- Untouched: `docs/superpowers/specs/2026-09-20-damnit-nvim-design.md`

**Interfaces:**

- Consumes: nothing.
- Produces: `require("damnit")`, `require("damnit.<name>")`, the `:Dam` user command, the
  `vim.g.loaded_damnit` guard, and `:checkhealth damnit`. Every later task names modules this way.

- [ ] **Step 1: Record the green baseline**

Run: `nvim --headless --clean -l tests/run.lua | tail -1`
Expected: `259 passed, 0 failed in 2.10s`, give or take the seconds.

- [ ] **Step 2: Move the files**

```bash
git mv lua/todoist lua/damnit
git mv plugin/todoist.lua plugin/damnit.lua
```

- [ ] **Step 3: Rewrite every reference**

`perl -pi` rather than `sed -i`, because BSD and GNU `sed` disagree about `-i` and this repository is
developed on macOS and tested on Linux. The Todoist API host and `TODOIST_SPEC_TOKEN` are deliberately
not in the list: they name the service, and they leave with the client in Task 2.

```bash
perl -pi -e '
  s{require\("todoist}{require("damnit}g;
  s{todoist\.nvim}{damnit.nvim}g;
  s{\btodoist\.(CompletedRequest|Error|ListSpec|Location|Options|Request|SidebarOptions|Tree)\b}{damnit.$1}g;
  s{vim\.g\.loaded_todoist}{vim.g.loaded_damnit}g;
  s{checkhealth todoist}{checkhealth damnit}g;
  s{plugin/todoist\.lua}{plugin/damnit.lua}g;
  s{:Todoist\b}{:Dam}g;
  s{"Todoist"}{"Dam"}g;
  s{desc = "Todoist: }{desc = "dam: }g;
' $(git ls-files 'lua/*.lua' 'plugin/*.lua' 'tests/*.lua' README.md)
```

- [ ] **Step 4: Read what is left and decide each one**

Run: `grep -rniE 'todoist' lua plugin tests README.md`
Expected: only three kinds of hit, all of which stay for now: `api.todoist.com` in
`lua/damnit/client.lua`, `TODOIST_SPEC_TOKEN` in `tests/client_spec.lua` and `tests/token_spec.lua`, and
prose naming the Todoist service in files Task 2 deletes. A hit anywhere else is a missed expression;
fix it by hand.

- [ ] **Step 5: Run the suite**

Run: `nvim --headless --clean -l tests/run.lua | tail -1`
Expected: `259 passed, 0 failed`, the same count as Step 1.

- [ ] **Step 6: Lint**

Run: `stylua --check . && luacheck .`
Expected: both silent, exit 0.

- [ ] **Step 7: Commit**

```bash
git add -A
SKIP_AI_COMMIT=1 git commit -m "refactor: rename the plugin to damnit.nvim in place"
```

---

### Task 2: Strip the network half

Everything that exists to reach Todoist goes, and everything that cannot work without it goes with it,
so the repository is green rather than half-ported. What survives is the pure layer, the harness and the
options. The feature modules come back one task at a time on the `dam` boundary, and each of those tasks
restores its file from this commit's parent with `git show` rather than retyping it.

**Files:**

- Delete: `lua/damnit/client.lua`, `token.lua`, `completed.lua`, `completed_history.lua`, `list.lua`,
  `quick_edit.lua`, `picker.lua`, `sidebar.lua`, `capture.lua`, `send.lua`, `status.lua`,
  `task_buffer.lua`, `health.lua`, `plugin/damnit.lua`
- Delete: `tests/client_spec.lua`, `token_spec.lua`, `completed_history_spec.lua`,
  `completed_loopback_spec.lua`, `loopback_spec.lua`, `list_spec.lua`, `list_loopback_spec.lua`,
  `quick_edit_spec.lua`, `quick_edit_loopback_spec.lua`, `picker_spec.lua`, `sidebar_spec.lua`,
  `capture_spec.lua`, `send_spec.lua`, `status_spec.lua`, `subtask_tree_spec.lua`,
  `task_buffer_spec.lua`
- Keep: `lua/damnit/init.lua`, `tree.lua`, `task_format.lua`, `list_format.lua`, `location.lua`,
  `due.lua`, and `tests/tree_spec.lua`, `task_format_spec.lua`, `list_format_spec.lua`,
  `location_spec.lua`, `due_spec.lua`
- Modify: `lua/damnit/init.lua`, `tests/run.lua`

**Interfaces:**

- Consumes: the renamed tree from Task 1.
- Produces: a plugin with no user command, no network code and no credential. `require("damnit").options`
  still exists and still carries `views`, `picker`, `sidebar`, `refresh_interval` and `reminders`;
  Task 3 reshapes it.

- [ ] **Step 1: Delete the files**

```bash
git rm lua/damnit/client.lua lua/damnit/token.lua lua/damnit/completed.lua \
  lua/damnit/completed_history.lua lua/damnit/list.lua lua/damnit/quick_edit.lua \
  lua/damnit/picker.lua lua/damnit/sidebar.lua lua/damnit/capture.lua lua/damnit/send.lua \
  lua/damnit/status.lua lua/damnit/task_buffer.lua lua/damnit/health.lua plugin/damnit.lua
git rm tests/client_spec.lua tests/token_spec.lua tests/completed_history_spec.lua \
  tests/completed_loopback_spec.lua tests/loopback_spec.lua tests/list_spec.lua \
  tests/list_loopback_spec.lua tests/quick_edit_spec.lua tests/quick_edit_loopback_spec.lua \
  tests/picker_spec.lua tests/sidebar_spec.lua tests/capture_spec.lua tests/send_spec.lua \
  tests/status_spec.lua tests/subtask_tree_spec.lua tests/task_buffer_spec.lua
```

- [ ] **Step 2: Cut `init.lua` down to what still exists**

Replace the whole of `lua/damnit/init.lua` with this. `view`, `open`, `pick`, `completed`, `status` and
`toggle` all called modules that are gone, so they go too and come back in the tasks that rebuild them.

```lua
-- damnit.nvim: the dam task store from inside the editor.
--
-- Options and nothing else, read when a call is made rather than copied into
-- the caller, so a `setup` later in a session changes the next call.

local M = {}

--- Every option at its default.
---@class damnit.Options
---@field views table<string, string> a view name to the dam query it runs
---@field picker "auto"|"fzf-lua"|"select" which front end the task search uses
---@field sidebar damnit.SidebarOptions how `toggle` puts a view beside your work
---@field refresh_interval integer seconds between the background reads behind `status()`
---@field reminders boolean whether a task with a time raises a notification when it comes due
M.options = {
  views = {},
  picker = "auto",
  sidebar = {
    side = "left",
    width = 40,
    view = "today",
  },
  refresh_interval = 60,
  reminders = false,
}

--- The sidebar's own options.
---@class damnit.SidebarOptions
---@field side "left"|"right" the edge the split sits on
---@field width integer columns the split is held at
---@field view string the name of the view it opens

---@param opts damnit.Options?
function M.setup(opts)
  -- Deep, so naming one sidebar option keeps the defaults of the others.
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
```

- [ ] **Step 3: Correct the runner's header comment**

In `tests/run.lua`, replace the third paragraph, which describes a fake `vim.system` and a loopback HTTP
server that no longer exist:

```lua
-- No spec reaches the network and no spec runs the real `dam`. Task 4 puts a
-- fake `dam` at the front of PATH; until then every spec here is a pure one.
```

- [ ] **Step 4: Run the suite**

Run: `nvim --headless --clean -l tests/run.lua | tail -1`
Expected: five specs run and pass. The count drops from 259 to the cases in `tree_spec`,
`task_format_spec`, `list_format_spec`, `location_spec` and `due_spec`. Nothing fails.

- [ ] **Step 5: Prove the credential is gone**

Run: `grep -rniE 'token|credential|api\.todoist' lua plugin tests`
Expected: no output at all.

- [ ] **Step 6: Lint and commit**

```bash
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "refactor: delete the Todoist client, the token and the features built on them"
```

---

### Task 3: The message prefix and the dam-shaped options

Two small pieces every later task uses: the one place that writes the `damnit.nvim: ` prefix, and the
options `dam` needs.

**Files:**

- Create: `lua/damnit/message.lua`
- Create: `tests/message_spec.lua`
- Modify: `lua/damnit/init.lua`

**Interfaces:**

- Consumes: `require("damnit").options` from Task 2.
- Produces: `message.say(text)`, `message.warn(text)`, `message.fail(text)`, `message.report(err)` where
  `err` is the `damnit.Error` of Task 4; and `options.store`, `options.config`, `options.timeout`,
  `options.window.float`.

- [ ] **Step 1: Write the failing test**

Create `tests/message_spec.lua`:

```lua
-- The prefix rule: what this plugin says carries its name, what dam said does
-- not, so the two are never confused in a notification.

local message = require("damnit.message")

---@param run fun()
---@return { text: string, level: integer }[]
local function notifications(run)
  local seen = {}
  local real = vim.notify
  vim.notify = function(text, level)
    table.insert(seen, { text = text, level = level })
  end

  local ok, err = pcall(run)

  vim.notify = real
  assert(ok, err)

  return seen
end

return {
  ["prefixes what the plugin itself says"] = function()
    local seen = notifications(function()
      message.warn("nothing is staged")
    end)

    assert(#seen == 1, vim.inspect(seen))
    assert(seen[1].text == "damnit.nvim: nothing is staged", seen[1].text)
    assert(seen[1].level == vim.log.levels.WARN, tostring(seen[1].level))
  end,

  ["carries dam's own wording unprefixed"] = function()
    local seen = notifications(function()
      message.report({ kind = "refused", code = 4, message = "78b8950 cannot be completed" })
    end)

    assert(seen[1].text == "78b8950 cannot be completed", seen[1].text)
    assert(seen[1].level == vim.log.levels.WARN, tostring(seen[1].level))
  end,

  ["prefixes an error the plugin wrote about dam rather than one dam wrote"] = function()
    local seen = notifications(function()
      message.report({ kind = "missing", code = -1, message = "dam was not found on PATH", plugin = true })
    end)

    assert(seen[1].text == "damnit.nvim: dam was not found on PATH", seen[1].text)
    assert(seen[1].level == vim.log.levels.ERROR, tostring(seen[1].level))
  end,
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua message_spec`
Expected: three FAIL lines, each `module 'damnit.message' not found`.

- [ ] **Step 3: Write the module**

Create `lua/damnit/message.lua`:

```lua
-- What the user is told, and who is speaking.
--
-- A sentence this plugin wrote is prefixed with its name. A sentence `dam` wrote
-- is passed through as dam wrote it. The prefix is the only way to tell them
-- apart in a notification, so it is written in exactly one place.

local M = {}

M.PREFIX = "damnit.nvim: "

---@param text string
---@param level integer
local function notify(text, level)
  vim.notify(text, level)
end

--- An outcome the user asked for.
---@param text string
function M.say(text)
  notify(M.PREFIX .. text, vim.log.levels.INFO)
end

--- A refusal or a failure the user can act on.
---@param text string
function M.warn(text)
  notify(M.PREFIX .. text, vim.log.levels.WARN)
end

--- A configuration problem that makes the plugin unusable.
---@param text string
function M.fail(text)
  notify(M.PREFIX .. text, vim.log.levels.ERROR)
end

--- One error table, at the level its kind deserves.
---
--- `plugin` marks a message this plugin composed, which is the only kind that
--- takes the prefix. Everything else is dam's own line.
---@param err damnit.Error
function M.report(err)
  local level = err.kind == "missing" and vim.log.levels.ERROR or vim.log.levels.WARN

  if err.plugin then
    return notify(M.PREFIX .. err.message, level)
  end

  notify(err.message, level)
end

return M
```

- [ ] **Step 4: Run it and watch it pass**

Run: `nvim --headless --clean -l tests/run.lua message_spec`
Expected: three `ok message_spec:` lines, `3 passed, 0 failed`.

- [ ] **Step 5: Add the dam options**

In `lua/damnit/init.lua`, add four fields to the class block and to `M.options`. `store` and `config`
are unset by default so that dam's own resolution and the `DAM_STORE` and `DAM_CONFIG` environment
variables keep working.

```lua
---@field store string? the store to pass as `--store`, or nil for dam's own resolution
---@field config string? the config to pass as `--config`, or nil for dam's own resolution
---@field timeout integer seconds one `dam` call may run before it is stopped
---@field window damnit.WindowOptions how the status window opens
```

```lua
  store = nil,
  config = nil,
  timeout = 120,
  window = {
    float = false,
  },
```

And the class for the new table, below `damnit.SidebarOptions`:

```lua
--- The status window's own options.
---@class damnit.WindowOptions
---@field float boolean open a centred float instead of a horizontal split
```

- [ ] **Step 6: Run the whole suite, lint and commit**

Run: `nvim --headless --clean -l tests/run.lua | tail -1`
Expected: the Task 2 count plus 3, `0 failed`.

```bash
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: add the message prefix rule and the dam store options"
```

---

### Task 4: The dam boundary, the handshake, and the fake dam

The only module in the plugin that spawns a process, and the test harness every later task uses. A fake
`dam` shell script at the front of `PATH` replaces the old fake `vim.system`, which means the real
spawn, the real argv, the real exit code and the real standard error are all exercised.

**Files:**

- Create: `lua/damnit/dam.lua`, `lua/damnit/answer.lua`
- Create: `tests/helpers/fake_dam.lua`
- Create: `tests/fixtures/default/status.json`
- Create: `tests/dam_spec.lua`, `tests/handshake_spec.lua`, `tests/answer_spec.lua`
- Modify: `lua/damnit/init.lua` (`setup` forgets the handshake)

**Interfaces:**

- Consumes: `require("damnit").options.store`, `.config`, `.timeout`; `damnit.message`.
- Produces:
  - `dam.argv(args) -> string[]`, the full argv including `dam` and any `--store`/`--config`.
  - `dam.call(args, opts, callback)` where `opts` is `{ label: string?, on_spawn: fun(handle) }?` and
    `callback` is `fun(data: table?, err: damnit.Error?)`. This is the one entry point every caller uses.
  - `answer.interpret(out, label) -> table?, damnit.Error?`, pure over a `vim.SystemCompleted`,
    and `answer.MISSING`, the sentence for a dam that is not on `PATH`.
  - `dam.supported(version) -> boolean`, `dam.forget()`, `dam.version` (a string or nil).
  - `damnit.Error` = `{ kind, code, message, rule, oids, plugin }`. `kind` is dam's own word where
    dam wrote a document (`refused`, `store`, `helper`, `credential`, `parse`, `usage`,
    `cancelled`), and otherwise this plugin's own (`error`, `usage`, `cancelled`, `timeout`,
    `missing`, `unsupported`, `malformed`). `rule` and `oids` come from the document.
  - The fake: `fake.install(opts) -> handle`, `fake.argv_log(handle) -> string[]`,
    `fake.settle(done, ms)`, `fake.remove(handle)`.

- [ ] **Step 1: Write the fake dam harness**

Create `tests/helpers/fake_dam.lua`. This is test scaffolding rather than a behaviour, so it lands
before its first failing test.

```lua
-- A fake `dam` at the front of PATH.
--
-- Four environment variables drive every case: which fixture directory to read,
-- how long to sleep, what to write on standard error, and what to exit with.
-- The argv log is what every assertion about "what the plugin sent" reads.

local M = {}

local SCRIPT = [==[#!/bin/sh
# Records its argv, then replays the fixture named for its subcommand.
printf '%s\n' "$*" >> "$DAMNIT_TEST_LOG"

case "$1" in
  --version) echo "dam ${DAMNIT_TEST_VERSION:-0.2.0}"; exit 0 ;;
esac

# The subcommand is the first argument that is not a flag and is not the value
# of one, so `--store /tmp/x status --json` still finds `status`.
subcommand=""
skip=0
for arg in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$arg" in
    --store|--config) skip=1 ;;
    -*) ;;
    *) subcommand="$arg"; break ;;
  esac
done

# dam exits 3 on an interrupt. The sleep runs in the background and the script
# waits on it, so the trap runs the moment the signal arrives.
trap 'exit 3' INT
trap 'exit 3' TERM
if [ -n "$DAMNIT_TEST_SLEEP" ]; then sleep "$DAMNIT_TEST_SLEEP" & wait $!; fi

if [ -n "$DAMNIT_TEST_STDERR" ]; then printf '%s\n' "$DAMNIT_TEST_STDERR" >&2; fi
if [ -n "$DAMNIT_TEST_EXIT" ] && [ "$DAMNIT_TEST_EXIT" != 0 ]; then exit "$DAMNIT_TEST_EXIT"; fi

cat "$DAMNIT_TEST_FIXTURES/$subcommand.json"
]==]

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local VARIABLES = {
  "DAMNIT_TEST_LOG",
  "DAMNIT_TEST_FIXTURES",
  "DAMNIT_TEST_VERSION",
  "DAMNIT_TEST_SLEEP",
  "DAMNIT_TEST_STDERR",
  "DAMNIT_TEST_EXIT",
}

---@class damnit.FakeDam
---@field dir string the temporary directory the script lives in
---@field log string the path the argv log is appended to
---@field path string the PATH this fake replaced

--- Put a fake `dam` at the front of PATH.
---@param opts { fixtures: string?, version: string?, sleep: string?, stderr: string?, exit: integer? }?
---@return damnit.FakeDam
function M.install(opts)
  opts = opts or {}

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")

  local script = dir .. "/dam"
  local file = assert(io.open(script, "w"))
  file:write(SCRIPT)
  file:close()
  assert(vim.uv.fs_chmod(script, tonumber("755", 8)))

  local fake = { dir = dir, log = dir .. "/argv.log", path = vim.env.PATH }

  vim.env.PATH = dir .. ":" .. vim.env.PATH
  vim.env.DAMNIT_TEST_LOG = fake.log
  vim.env.DAMNIT_TEST_FIXTURES = opts.fixtures or (TESTS_DIR .. "/fixtures/default")
  vim.env.DAMNIT_TEST_VERSION = opts.version or "0.2.0"
  vim.env.DAMNIT_TEST_SLEEP = opts.sleep or ""
  vim.env.DAMNIT_TEST_STDERR = opts.stderr or ""
  vim.env.DAMNIT_TEST_EXIT = opts.exit and tostring(opts.exit) or ""

  require("damnit.dam").forget()

  return fake
end

--- Every argv line the fake recorded, in order, with the leading `dam` removed.
---@param fake damnit.FakeDam
---@return string[]
function M.argv_log(fake)
  local lines = {}

  local file = io.open(fake.log, "r")
  if not file then
    return lines
  end

  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()

  return lines
end

--- Turn the loop until `done` answers true. `vim.wait` is allowed here: this is
--- a test, and the whole point is to let the scheduled callback run.
---@param done fun(): boolean
---@param ms integer?
function M.settle(done, ms)
  assert(vim.wait(ms or 2000, done, 5), "the dam call never answered")
end

--- Take the fake away and put PATH back.
---@param fake damnit.FakeDam
function M.remove(fake)
  vim.env.PATH = fake.path
  vim.fn.delete(fake.dir, "rf")

  for _, name in ipairs(VARIABLES) do
    vim.env[name] = nil
  end

  require("damnit.dam").forget()
end

return M
```

- [ ] **Step 2: Write the smallest fixture**

Create `tests/fixtures/default/status.json`, a status with nothing in any section. Every field is
present because `dam status --json` always emits all five.

```json
{"staged": [], "unstaged": [], "conflicts": [], "notices": [], "unpushed": []}
```

- [ ] **Step 3: Write the failing tests**

Create `tests/dam_spec.lua`:

```lua
-- The dam boundary: the argv it builds, the JSON it decodes, and the error
-- table it makes of every exit code.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local dam = require("damnit.dam")
local damnit = require("damnit")

---@param opts table? passed to fake_dam.install
---@param args string[]
---@return table? data
---@return damnit.Error? err
---@return string[] argv_log
local function call(opts, args)
  local fake = fake_dam.install(opts)

  local answered, data, err = false, nil, nil
  dam.call(args, nil, function(value, failure)
    answered, data, err = true, value, failure
  end)

  fake_dam.settle(function()
    return answered
  end)

  local log = fake_dam.argv_log(fake)
  fake_dam.remove(fake)

  return data, err, log
end

return {
  ["builds an argv with no store flags when neither option is set"] = function()
    damnit.options.store, damnit.options.config = nil, nil

    assert(vim.deep_equal(dam.argv({ "status", "--json" }), { "dam", "status", "--json" }))
  end,

  ["passes --store and --config through as global flags, before the subcommand"] = function()
    damnit.options.store, damnit.options.config = "/store/dam.db", "/config/dam.toml"

    local argv = dam.argv({ "status", "--json" })
    damnit.options.store, damnit.options.config = nil, nil

    assert(
      vim.deep_equal(argv, {
        "dam",
        "--store",
        "/store/dam.db",
        "--config",
        "/config/dam.toml",
        "status",
        "--json",
      }),
      vim.inspect(argv)
    )
  end,

  ["decodes the JSON dam printed on a clean exit"] = function()
    local data, err, log = call(nil, { "status", "--json" })

    assert(err == nil, err and err.message)
    assert(type(data) == "table" and vim.islist(data.staged), vim.inspect(data))
    assert(log[#log] == "status --json", vim.inspect(log))
  end,

  ["calls exit 1 an error and strips dam's own prefix off the line"] = function()
    local _, err = call({ exit = 1, stderr = "dam: storage: the store is locked" }, { "add", "78b8950", "--json" })

    assert(err.kind == "error", err.kind)
    assert(err.code == 1, tostring(err.code))
    assert(err.message == "storage: the store is locked", err.message)
    assert(err.plugin == nil, "dam wrote this message, so it takes no prefix")
  end,

  ["reads a refusal out of dam's error document, rule and oids included"] = function()
    -- dam writes a header, one indented line per blocker, then its advice.
    local blocked = "98d8780 cannot be completed:\n  child a9db854 is open\n"
      .. "use --force to complete it anyway, or --force --interactive to decide what happens to them"
    local document = vim.json.encode({
      error = {
        kind = "refused",
        rule = "blocked",
        message = blocked,
        oids = { "98d878013fb0e026d37170e7ceed6707192ae99a", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77" },
      },
    })
    local _, err = call({ exit = 4, stderr = document }, { "done", "98d8780", "--json" })

    assert(err.kind == "refused", err.kind)
    assert(err.code == 4, tostring(err.code))
    assert(err.rule == "blocked", tostring(err.rule))
    assert(err.message == blocked, vim.inspect(err.message))
    assert(#err.oids == 2 and err.oids[2]:sub(1, 7) == "a9db854", vim.inspect(err.oids))
    assert(err.plugin == nil, "dam wrote this message, so it takes no prefix")
  end,

  ["carries standard error that is not a document as the message it is"] = function()
    local usage = "error: unrecognized subcommand 'dpne'\n\nUsage: dam <COMMAND>"
    local _, err = call({ exit = 2, stderr = usage }, { "dpne", "--json" })

    assert(err.kind == "usage", err.kind)
    assert(err.rule == nil, "clap wrote this, so there is no rule")
    assert(err.message == usage, vim.inspect(err.message))
  end,

  ["calls exit 3 cancelled"] = function()
    local _, err = call({ exit = 3, stderr = "dam: cancelled" }, { "push", "--json" })

    assert(err.kind == "cancelled", err.kind)
    assert(err.code == 3, tostring(err.code))
  end,

  ["calls an undecodable answer on a clean exit malformed rather than raising"] = function()
    local fake = fake_dam.install()
    vim.env.DAMNIT_TEST_FIXTURES = fake.dir

    local file = assert(io.open(fake.dir .. "/status.json", "w"))
    file:write("not json at all\n")
    file:close()

    local answered, err = false, nil
    dam.call({ "status", "--json" }, nil, function(_, failure)
      answered, err = true, failure
    end)

    fake_dam.settle(function()
      return answered
    end)
    fake_dam.remove(fake)

    assert(err.kind == "malformed", vim.inspect(err))
    assert(err.plugin == true, "the plugin wrote this one")
  end,

  ["reports a dam that is not on PATH instead of raising"] = function()
    local saved = vim.env.PATH
    vim.env.PATH = "/nonexistent-for-this-spec"
    dam.forget()

    local answered, err = false, nil
    local ok = pcall(dam.call, { "status", "--json" }, nil, function(_, failure)
      answered, err = true, failure
    end)

    fake_dam.settle(function()
      return answered
    end)

    vim.env.PATH = saved
    dam.forget()

    assert(ok, "a missing binary must not raise out of dam.call")
    assert(err.kind == "missing", vim.inspect(err))
    assert(err.message:find("cargo install damnit", 1, true), err.message)
  end,
}
```

Create `tests/handshake_spec.lua`:

```lua
-- The version handshake: what the plugin accepts, what it refuses for the rest
-- of the session, and what it shrugs at.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local dam = require("damnit.dam")

---@param version string what the fake prints for `dam --version`
---@return damnit.Error? err
---@return string[] notifications
---@return string[] argv_log
local function first_call(version)
  local fake = fake_dam.install({ version = version })

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local answered, err = false, nil
  dam.call({ "status", "--json" }, nil, function(_, failure)
    answered, err = true, failure
  end)

  fake_dam.settle(function()
    return answered
  end)

  vim.notify = real
  local log = fake_dam.argv_log(fake)
  fake_dam.remove(fake)

  return err, notifications, log
end

return {
  ["accepts 0.2.0 and goes on to make the call"] = function()
    local err, _, log = first_call("0.2.0")

    assert(err == nil, err and err.message)
    assert(log[1] == "--version", vim.inspect(log))
    assert(log[2] == "status --json", vim.inspect(log))
  end,

  ["refuses a version above the range and never spawns the call"] = function()
    local err, _, log = first_call("0.9.0")

    assert(err.kind == "unsupported", vim.inspect(err))
    assert(
      err.message == "dam 0.9.0 is outside the supported range >=0.2.0 <0.3.0; update damnit.nvim",
      err.message
    )
    assert(#log == 1 and log[1] == "--version", vim.inspect(log))
  end,

  ["refuses 0.3.0, which is the first version outside the range"] = function()
    assert(dam.supported("0.2.0"))
    assert(dam.supported("0.2.9"))
    assert(not dam.supported("0.3.0"))
    assert(not dam.supported("0.1.9"))
  end,

  ["warns once about a banner it cannot read, then makes the call anyway"] = function()
    local err, notifications, log = first_call("banana")

    assert(err == nil, err and err.message)
    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("is not a version", 1, true), notifications[1])
    assert(log[2] == "status --json", vim.inspect(log))
  end,

  ["runs the handshake once per session, not once per call"] = function()
    local fake = fake_dam.install()

    for _ = 1, 3 do
      local answered = false
      dam.call({ "status", "--json" }, nil, function()
        answered = true
      end)
      fake_dam.settle(function()
        return answered
      end)
    end

    local log = fake_dam.argv_log(fake)
    fake_dam.remove(fake)

    local versions = 0
    for _, line in ipairs(log) do
      if line == "--version" then
        versions = versions + 1
      end
    end

    assert(versions == 1, vim.inspect(log))
  end,
}
```

- [ ] **Step 4: Run them and watch them fail**

Run: `nvim --headless --clean -l tests/run.lua dam_spec`
Expected: every case FAILs with `module 'damnit.dam' not found`.

- [ ] **Step 5: Write the module**

Create `lua/damnit/dam.lua`:

```lua
-- The one module that spawns a process.
--
-- Every call is argv, never a shell string, so a subject holding a quote or a
-- newline is an argument and nothing else. Every call carries `--json`. Every
-- result is marshalled through `vim.schedule` before it reaches the caller,
-- because a `vim.system` callback runs on the libuv loop where most of the API
-- is not allowed.

local M = {}

local message = require("damnit.message")

--- The dam versions this plugin speaks to, low inclusive and high exclusive.
M.MIN_VERSION = "0.2.0"
M.MAX_VERSION = "0.3.0"

M.MISSING = "dam was not found on PATH; install it with cargo install damnit"

--- Exit code to error kind, for a failure that carried no document. 0 is
--- success and is handled before this table. dam's own kind is used instead
--- wherever it wrote one.
local KINDS = { [1] = "error", [2] = "usage", [3] = "cancelled", [4] = "refused" }

--- The version this session read, or nil when the banner was unreadable.
---@type string?
M.version = nil

---@type "unknown"|"ok"|"refused"
local state = "unknown"

---@type damnit.Error?
local refusal = nil

---@type fun(err: damnit.Error?)[]
local waiting = {}

---@class damnit.Error
---@field kind string dam's own kind where it wrote one, this plugin's otherwise
---@field code integer the exit code, or -1 when nothing ran
---@field message string ready to show: dam's own sentence, or this plugin's
---@field rule string? the rule a refusal broke, as dam names it
---@field oids string[]? the objects dam's message names, in the order it names them
---@field plugin boolean? true when this plugin composed the message

--- The full argv for a call, `dam` and the global flags included.
---@param args string[] the subcommand and its flags, `--json` included
---@return string[]
function M.argv(args)
  local options = require("damnit").options
  local argv = { "dam" }

  for _, flag in ipairs({ "store", "config" }) do
    local value = options[flag]
    if type(value) == "string" and value ~= "" then
      vim.list_extend(argv, { "--" .. flag, value })
    end
  end

  vim.list_extend(argv, args)

  return argv
end

--- Standard error that is not a document: clap's own usage text, or the plain
--- line a human format writes.
---@param stderr string?
---@return string
function M.message_of(stderr)
  local text = vim.trim(tostring(stderr or ""))

  return (text:gsub("^dam: ", ""))
end

--- The error document dam writes on standard error under --json, or nil when
--- standard error holds something else.
---@param stderr string?
---@return table?
local function document_of(stderr)
  local text = vim.trim(tostring(stderr or ""))
  if text == "" then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, text, { luanil = { object = true } })
  if not ok or type(decoded) ~= "table" or type(decoded.error) ~= "table" then
    return nil
  end

  return decoded.error
end

---@param text string
---@return integer[]? parts
local function parts_of(text)
  local major, minor, patch = tostring(text):match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

---@param left integer[]
---@param right integer[]
---@return integer -1, 0 or 1
local function compare(left, right)
  for index = 1, 3 do
    if left[index] ~= right[index] then
      return left[index] < right[index] and -1 or 1
    end
  end

  return 0
end

--- Whether a version string is one this plugin speaks to.
---@param text string
---@return boolean
function M.supported(text)
  local parts = parts_of(text)
  if not parts then
    return false
  end

  return compare(parts, parts_of(M.MIN_VERSION)) >= 0 and compare(parts, parts_of(M.MAX_VERSION)) < 0
end

--- One finished process into a result or an error.
---@param out table a vim.SystemCompleted, or one this module synthesised
---@param label string? what to call the call in a timeout message
---@return table? data
---@return damnit.Error? err
function M.interpret(out, label)
  if out.missing then
    return nil, { kind = "missing", code = -1, plugin = true, message = M.MISSING }
  end

  if out.code == 0 then
    local ok, decoded = pcall(vim.json.decode, out.stdout or "", { luanil = { object = true } })
    if not ok or type(decoded) ~= "table" then
      return nil,
        { kind = "malformed", code = 0, plugin = true, message = "dam answered with something that is not JSON" }
    end

    return decoded, nil
  end

  if out.code == 124 then
    local seconds = tonumber(require("damnit").options.timeout) or 120

    return nil, {
      kind = "timeout",
      code = 124,
      plugin = true,
      message = ("%s took longer than %ds and was stopped"):format(label or "a dam call", seconds),
    }
  end

  local document = document_of(out.stderr)
  if document then
    return nil, {
      kind = type(document.kind) == "string" and document.kind or (KINDS[out.code] or "error"),
      code = out.code,
      rule = document.rule,
      oids = document.oids,
      message = tostring(document.message or ""),
    }
  end

  local text = M.message_of(out.stderr)
  if text == "" then
    return nil, {
      kind = KINDS[out.code] or "error",
      code = out.code,
      plugin = true,
      message = ("%s failed with exit %d and said nothing"):format(label or "a dam call", out.code),
    }
  end

  return nil, { kind = KINDS[out.code] or "error", code = out.code, message = text }
end

--- Spawn one `dam`, answering on the main loop.
---
--- `vim.system` throws when the binary is absent rather than calling back, so
--- the spawn is wrapped and the absence arrives as an ordinary answer.
---@param args string[]
---@param on_exit fun(out: table)
---@return table? handle
local function spawn(args, on_exit)
  local seconds = math.max(tonumber(require("damnit").options.timeout) or 120, 1)

  local ok, handle = pcall(vim.system, M.argv(args), { text = true, timeout = seconds * 1000 }, function(out)
    vim.schedule(function()
      on_exit(out)
    end)
  end)

  if not ok then
    vim.schedule(function()
      on_exit({ code = -1, stdout = "", stderr = "", missing = true })
    end)

    return nil
  end

  return handle
end

--- Answer every caller waiting on the handshake, then clear the list.
---@param err damnit.Error?
local function settle_handshake(err)
  local callbacks = waiting
  waiting = {}

  for _, callback in ipairs(callbacks) do
    callback(err)
  end
end

--- Read `dam --version` once per session and decide whether to speak to it.
---@param callback fun(err: damnit.Error?)
local function handshake(callback)
  if state == "ok" then
    return callback(nil)
  end

  if state == "refused" then
    return callback(refusal)
  end

  table.insert(waiting, callback)
  if #waiting > 1 then
    return
  end

  spawn({ "--version" }, function(out)
    local banner = vim.trim(tostring(out.stdout or ""))
    local version = banner:match("dam%s+(%d+%.%d+%.%d+)")

    if out.missing or (out.code ~= 0 and not version) then
      state = "refused"
      refusal = { kind = "missing", code = -1, plugin = true, message = M.MISSING }
    elseif not version then
      -- An unreadable banner is not a reason to refuse to work. A wrong JSON
      -- shape fails loudly at the call that needs it.
      state = "ok"
      M.version = nil
      message.warn(("dam --version printed %q, which is not a version; going on anyway"):format(banner))
    elseif not M.supported(version) then
      state = "refused"
      refusal = {
        kind = "unsupported",
        code = 0,
        plugin = true,
        message = ("dam %s is outside the supported range >=%s <%s; update damnit.nvim"):format(
          version,
          M.MIN_VERSION,
          M.MAX_VERSION
        ),
      }
    else
      state = "ok"
      M.version = version
    end

    settle_handshake(state == "ok" and nil or refusal)
  end)
end

--- Forget the handshake, so the next call runs it again. `setup` calls this,
--- because new options may name a different dam.
function M.forget()
  state = "unknown"
  refusal = nil
  waiting = {}
  M.version = nil
end

--- Make one `dam` call. The one entry point every other module uses.
---@param args string[] the subcommand and its flags, `--json` included
---@param opts { label: string?, on_spawn: fun(handle: table?) }?
---@param callback fun(data: table?, err: damnit.Error?)
function M.call(args, opts, callback)
  opts = opts or {}

  handshake(function(err)
    if err then
      return callback(nil, err)
    end

    local handle = spawn(args, function(out)
      callback(M.interpret(out, opts.label))
    end)

    if opts.on_spawn then
      opts.on_spawn(handle)
    end
  end)
end

return M
```

- [ ] **Step 6: Make `setup` forget the handshake**

In `lua/damnit/init.lua`, at the end of `M.setup`:

```lua
  -- A handshake made under the old options is not the one the new options name.
  require("damnit.dam").forget()
```

- [ ] **Step 7: Run both specs and watch them pass**

Run: `nvim --headless --clean -l tests/run.lua dam_spec && nvim --headless --clean -l tests/run.lua handshake_spec`
Expected: `8 passed, 0 failed` then `5 passed, 0 failed`, each in well under a second.

- [ ] **Step 8: Run the whole suite, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua | tail -1
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: add the dam process boundary and its version handshake"
```

**What landed on top of this transcription.** Four behaviours the module above does not have, each
found by a measurement rather than by reading:

1. A handshake carries the generation `forget` was at, and a probe whose generation has moved on
   writes nothing, so an answer under the old options cannot decide the new session's state.
1. `forget` answers every caller waiting on the handshake with a cancellation before clearing the
   list. Dropping them silently leaves a queue lane running for the rest of the session.
1. `interpret` checks `out.signal` before `out.code`: Neovim reports code 0 with the signal set for
   a child a signal killed, so an unguarded code 0 reads every rung of the cancellation ladder as an
   empty answer.
1. A failure that wrote nothing at all on standard error gets a sentence naming the call and the
   exit code, rather than an empty notification. So does a document whose own message is empty,
   which names dam's rule or its kind instead of the exit code.
1. A document's `rule` and `oids` are kept only in the shapes dam sends, a string and a list of
   strings, because the first thing a caller does with `oids` is iterate it.
1. The module is two: `dam.lua` spawns and shakes hands, `answer.lua` reads one finished process,
   and `tests/answer_spec.lua` holds the cases that drive `interpret` directly. `answer.lua` is
   pure in the sense the constraints use, so it belongs in Task 27's list.

---

### Task 5: The per-store queue, non-blocking, and cancellation

One `dam` per store at a time. Local calls queue; a second network call is refused. The queue owns the
elapsed timer and the cancellation ladder, and this task also lands the test that proves the editor
never stops.

**Files:**

- Create: `lua/damnit/queue.lua`
- Create: `tests/queue_spec.lua`, `tests/nonblocking_spec.lua`
- Create: `tests/fixtures/default/push.json`

**Interfaces:**

- Consumes: `dam.call`, `message.warn`.
- Produces:
  - `queue.key() -> string`, the store key: `opts.store`, else `DAM_STORE`, else `"default"`.
  - `queue.submit(entry) -> boolean`, with
    `entry = { args, label, verb?, network?, on_done? }`.
  - `queue.running(key?) -> { label, elapsed, pending }?`
  - `queue.cancel(key?) -> boolean`
  - `queue.on_tick(fn)`, called with the store key every `queue.TICK_MS` while anything runs.
  - `queue.reset()`, for specs only.
  - `queue.TICK_MS = 250`, `queue.GRACE_MS = 2000`, both constants a spec lowers.

- [ ] **Step 1: Add the push fixture**

Create `tests/fixtures/default/push.json`:

```json
{"remotes": [{"remote": "todoist", "sent": 3, "succeeded": 3, "skipped": 0, "failed": []}]}
```

- [ ] **Step 2: Write the failing queue test**

Create `tests/queue_spec.lua`:

```lua
-- The queue: one dam per store at a time, a refused second network call, and
-- what cancelling drops.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local damnit = require("damnit")

---@param run fun(fake: damnit.FakeDam, notifications: string[])
---@param opts table?
local function with_fake(run, opts)
  local fake = fake_dam.install(opts)
  queue.reset()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local ok, err = pcall(run, fake, notifications)

  vim.notify = real
  queue.reset()
  fake_dam.remove(fake)
  damnit.options.store = nil

  assert(ok, err)
end

---@param args string[]
---@param extra table?
---@return table entry
local function entry(args, extra)
  return vim.tbl_extend("force", { args = args, label = table.concat(args, " ") }, extra or {})
end

return {
  ["runs one entry at a time and holds the rest"] = function()
    with_fake(function()
      queue.submit(entry({ "status", "--json" }))
      queue.submit(entry({ "status", "--json" }))

      local running = queue.running()
      assert(running ~= nil, "the first entry starts as soon as it is submitted")
      assert(running.pending == 1, tostring(running.pending))
    end, { sleep = "0.3" })
  end,

  ["refuses a second push and names the one already running"] = function()
    with_fake(function(fake, notifications)
      assert(queue.submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true })))

      local second = queue.submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))

      assert(second == false, "the second push must be refused rather than queued")
      assert(#notifications == 1, vim.inspect(notifications))
      assert(
        notifications[1] == "damnit.nvim: push todoist is already running; C-c cancels it",
        notifications[1]
      )

      fake_dam.settle(function()
        return queue.running() == nil
      end, 3000)

      local pushes = 0
      for _, line in ipairs(fake_dam.argv_log(fake)) do
        if line == "push --json" then
          pushes = pushes + 1
        end
      end
      assert(pushes == 1, vim.inspect(fake_dam.argv_log(fake)))
    end, { sleep = "0.2" })
  end,

  ["tells a pull that a push is what is in the way"] = function()
    with_fake(function(_, notifications)
      queue.submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))
      queue.submit(entry({ "pull", "--json" }, { label = "pull todoist", verb = "pull", network = true }))

      assert(
        notifications[1] == "damnit.nvim: push todoist is running; C-c cancels it, then pull",
        notifications[1]
      )
    end, { sleep = "0.2" })
  end,

  ["queues a local call behind a running network one"] = function()
    with_fake(function()
      queue.submit(entry({ "push", "--json" }, { label = "push todoist", verb = "push", network = true }))

      assert(queue.submit(entry({ "status", "--json" })), "a local call queues rather than being refused")
      assert(queue.running().pending == 1, vim.inspect(queue.running()))
    end, { sleep = "0.2" })
  end,

  ["keeps a second store's lane independent of the first"] = function()
    with_fake(function()
      damnit.options.store = "/store/one.db"
      queue.submit(entry({ "status", "--json" }))

      damnit.options.store = "/store/two.db"
      queue.submit(entry({ "status", "--json" }))

      assert(queue.running("/store/one.db") ~= nil, "the first store is still running")
      assert(queue.running("/store/two.db") ~= nil, "the second store did not wait on the first")
    end, { sleep = "0.3" })
  end,

  ["says nothing is running when there is nothing to cancel"] = function()
    with_fake(function(_, notifications)
      assert(queue.cancel() == false)
      assert(notifications[1] == "damnit.nvim: nothing is running", notifications[1])
    end)
  end,
}
```

- [ ] **Step 3: Write the failing non-blocking test**

Create `tests/nonblocking_spec.lua`:

```lua
-- The requirement that prompted the whole design: nothing in this plugin takes
-- the editor hostage while dam runs.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")

return {
  ["returns at once and leaves the loop turning while dam runs"] = function()
    local fake = fake_dam.install({ sleep = "0.4" })
    queue.reset()

    local ticks = 0
    local observer = vim.uv.new_timer()
    observer:start(0, 20, function()
      ticks = ticks + 1
    end)

    local answered = false
    local began = vim.uv.hrtime()
    queue.submit({
      args = { "push", "--json" },
      label = "push todoist",
      verb = "push",
      network = true,
      on_done = function()
        answered = true
      end,
    })
    local submit_ms = (vim.uv.hrtime() - began) / 1e6

    fake_dam.settle(function()
      return answered
    end, 3000)

    observer:stop()
    observer:close()
    local log = fake_dam.argv_log(fake)
    fake_dam.remove(fake)
    queue.reset()

    assert(submit_ms < 100, ("submit took %.1fms, so something waited"):format(submit_ms))
    -- A blocking implementation produces zero ticks. The floor is generous on
    -- purpose: a ceiling around a real spawn is what reddens a build on a slow
    -- runner.
    assert(ticks >= 5, ("the loop ticked %d times while dam ran"):format(ticks))
    assert(log[#log] == "push --json", vim.inspect(log))
  end,

  ["cancels with SIGINT, which dam answers with exit 3"] = function()
    local fake = fake_dam.install({ sleep = "5" })
    queue.reset()
    local grace = queue.GRACE_MS
    queue.GRACE_MS = 20

    local answered, err = false, nil
    queue.submit({
      args = { "push", "--json" },
      label = "push todoist",
      verb = "push",
      network = true,
      on_done = function(_, failure)
        answered, err = true, failure
      end,
    })

    -- The handshake spawns first, so the push is the second recorded argv.
    fake_dam.settle(function()
      return #fake_dam.argv_log(fake) >= 2
    end)

    assert(queue.cancel())

    fake_dam.settle(function()
      return answered
    end)

    queue.GRACE_MS = grace
    fake_dam.remove(fake)
    queue.reset()

    assert(err ~= nil and err.kind == "cancelled", vim.inspect(err))
    assert(err.code == 3, tostring(err.code))
    assert(queue.running() == nil, "the lane is empty once the cancelled entry exits")
  end,

  ["drops the pending entries when the running one is cancelled"] = function()
    local fake = fake_dam.install({ sleep = "5" })
    queue.reset()
    local grace = queue.GRACE_MS
    queue.GRACE_MS = 20

    local ran = 0
    queue.submit({
      args = { "push", "--json" },
      label = "push todoist",
      verb = "push",
      network = true,
      on_done = function()
        ran = ran + 1
      end,
    })
    queue.submit({ args = { "status", "--json" }, label = "status" })
    queue.submit({ args = { "status", "--json" }, label = "status" })

    fake_dam.settle(function()
      return #fake_dam.argv_log(fake) >= 2
    end)

    assert(queue.running().pending == 2, vim.inspect(queue.running()))
    queue.cancel()

    fake_dam.settle(function()
      return queue.running() == nil
    end)

    queue.GRACE_MS = grace
    local log = fake_dam.argv_log(fake)
    fake_dam.remove(fake)
    queue.reset()

    assert(ran == 1, "the cancelled entry is still answered")
    for _, line in ipairs(log) do
      assert(line ~= "status --json", "a dropped entry must never spawn: " .. vim.inspect(log))
    end
  end,
}
```

- [ ] **Step 4: Run them and watch them fail**

Run: `nvim --headless --clean -l tests/run.lua queue_spec`
Expected: every case FAILs with `module 'damnit.queue' not found`.

- [ ] **Step 5: Write the module**

Create `lua/damnit/queue.lua`:

```lua
-- One dam process per store at a time.
--
-- This is what keeps the plugin from being a second writer against its own
-- SQLite store, and it is what makes a push and a pull impossible to overlap.
-- A read and a write share the lane: `dam status` is under 30 ms, and a fast
-- lane for reads would bring the concurrent-writer problem back the moment a
-- read pulls a stale remote.

local M = {}

local dam = require("damnit.dam")
local message = require("damnit.message")

--- How often the elapsed time is rewritten, and how long cancellation waits
--- between signals.
M.TICK_MS = 250
M.GRACE_MS = 2000

---@class damnit.Entry
---@field args string[] the subcommand and its flags, `--json` included
---@field label string what the header calls it, such as `push todoist`
---@field verb string? the word a refusal uses, such as `push`
---@field network boolean? whether this one reaches a remote
---@field on_done fun(data: table?, err: damnit.Error?)?
---@field started_at integer? vim.uv.hrtime when it began
---@field handle table?
---@field finished boolean?
---@field cancelled boolean?

---@class damnit.Lane
---@field running damnit.Entry?
---@field pending damnit.Entry[]
---@field timer uv.uv_timer_t?

---@type table<string, damnit.Lane>
local lanes = {}

---@type fun(key: string)[]
local listeners = {}

--- The store this session works against, which is the queue's key and the
--- status window's identity.
---@return string
function M.key()
  local store = require("damnit").options.store
  if type(store) == "string" and store ~= "" then
    return store
  end

  local env = vim.env.DAM_STORE
  if type(env) == "string" and env ~= "" then
    return env
  end

  return "default"
end

---@param key string
---@return damnit.Lane
local function lane_for(key)
  lanes[key] = lanes[key] or { pending = {} }

  return lanes[key]
end

---@param key string
local function tick(key)
  for _, listener in ipairs(listeners) do
    listener(key)
  end
end

---@param key string
---@param lane damnit.Lane
local function start_timer(key, lane)
  if lane.timer then
    return
  end

  lane.timer = vim.uv.new_timer()
  lane.timer:start(M.TICK_MS, M.TICK_MS, vim.schedule_wrap(function()
    tick(key)
  end))
end

---@param key string
---@param lane damnit.Lane
local function stop_timer(key, lane)
  if not lane.timer then
    return
  end

  lane.timer:stop()
  lane.timer:close()
  lane.timer = nil

  tick(key)
end

---@param key string
local function advance(key)
  local lane = lane_for(key)
  if lane.running then
    return
  end

  local entry = table.remove(lane.pending, 1)
  if not entry then
    stop_timer(key, lane)

    return
  end

  lane.running = entry
  entry.started_at = vim.uv.hrtime()
  start_timer(key, lane)

  dam.call(entry.args, {
    label = entry.label,
    on_spawn = function(handle)
      entry.handle = handle
    end,
  }, function(data, err)
    entry.finished = true
    lane.running = nil

    if entry.on_done then
      entry.on_done(data, err)
    end

    advance(key)
  end)
end

--- The network entry this lane already holds, running or waiting.
---@param lane damnit.Lane
---@return damnit.Entry?
local function network_entry(lane)
  if lane.running and lane.running.network then
    return lane.running
  end

  for _, entry in ipairs(lane.pending) do
    if entry.network then
      return entry
    end
  end

  return nil
end

--- Put one call in this store's lane.
---
--- A second network call is refused rather than queued: a queued push is a push
--- nobody asked for, against a store that has changed since they did, arriving
--- minutes later with no one watching.
---@param entry damnit.Entry
---@return boolean queued
function M.submit(entry)
  local key = M.key()
  local lane = lane_for(key)

  if entry.network then
    local busy = network_entry(lane)

    if busy then
      if busy.verb == entry.verb then
        message.warn(("%s is already running; C-c cancels it"):format(busy.label))
      else
        message.warn(("%s is running; C-c cancels it, then %s"):format(busy.label, entry.verb))
      end

      return false
    end
  end

  table.insert(lane.pending, entry)
  advance(key)

  return true
end

--- What is running in one store's lane, and how long it has been.
---@param key string?
---@return { label: string, elapsed: number, pending: integer }?
function M.running(key)
  local lane = lanes[key or M.key()]
  if not lane or not lane.running then
    return nil
  end

  return {
    label = lane.running.label,
    elapsed = (vim.uv.hrtime() - lane.running.started_at) / 1e9,
    pending = #lane.pending,
  }
end

---@param entry damnit.Entry
---@param signal string
local function escalate(entry, signal)
  local timer = vim.uv.new_timer()

  timer:start(M.GRACE_MS, 0, vim.schedule_wrap(function()
    timer:stop()
    timer:close()

    if entry.finished or not entry.handle then
      return
    end

    entry.handle:kill(signal)

    if signal == "sigterm" then
      return escalate(entry, "sigkill")
    end

    message.warn(("%s would not stop and was killed"):format(entry.label))
  end))
end

--- Stop what is running and drop what is waiting.
---@param key string?
---@return boolean cancelled
function M.cancel(key)
  key = key or M.key()
  local lane = lanes[key]

  if not lane or not lane.running then
    message.warn("nothing is running")

    return false
  end

  lane.pending = {}

  local entry = lane.running
  entry.cancelled = true

  if entry.handle then
    -- dam handles SIGINT, sets its cancellation flag and exits 3, so it gets to
    -- stop its helper and leave the store consistent.
    entry.handle:kill("sigint")
    escalate(entry, "sigterm")
  end

  return true
end

--- Call `fn` with the store key every tick while anything is running, and once
--- more when the lane empties.
---@param fn fun(key: string)
function M.on_tick(fn)
  table.insert(listeners, fn)
end

--- Drop every lane. Specs call it between cases; nothing in the plugin does.
function M.reset()
  for key, lane in pairs(lanes) do
    stop_timer(key, lane)
  end

  lanes = {}
end

return M
```

- [ ] **Step 6: Run both specs and watch them pass**

Run: `nvim --headless --clean -l tests/run.lua queue_spec && nvim --headless --clean -l tests/run.lua nonblocking_spec`
Expected: `6 passed, 0 failed` then `3 passed, 0 failed`. Check the reported seconds: both specs must
finish in well under a second each.

- [ ] **Step 7: Run the whole suite, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua | tail -1
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: add the per-store operation queue and its cancellation ladder"
```

**What landed on top of this transcription.** `on_spawn` sends the interrupt itself when the entry
was already cancelled, which is what makes `entry.cancelled` load-bearing. A cancel that arrives
while the version handshake is still running has no process to signal, and without this it dropped
the pending entries, reported success, and let the call spawn and reach the remote anyway.
`reset` clears the tick listeners as well as the lanes.

---

### Task 6: Views

A view is a name and a dam query. `opts.views` wins a collision with one of dam's own saved filters,
and a name in neither is refused with the declared names listed.

dam 0.1.0 has no command that lists its saved filters, so an undeclared name is handed to dam as a bare
word, which is how dam resolves a filter by name. dam's refusal is what teaches the plugin the name is
in neither source, and the plugin remembers that for the session so the second attempt costs no call.
Task 36 replaces the probe with a listing once dam has one.

**Files:**

- Create: `lua/damnit/views.lua`, `tests/views_spec.lua`

**Interfaces:**

- Consumes: `require("damnit").options.views`, `message.warn`.
- Produces:
  - `views.resolve(name) -> damnit.ListSpec?` where
    `damnit.ListSpec = { title: string, query: string?, probing: boolean? }`.
  - `views.query_args(spec) -> string[]`, the `ls` argv tail.
  - `views.forget_filter(name)`, called when dam refuses a probed name.
  - `views.declared() -> string[]`, sorted.

- [ ] **Step 1: Write the failing test**

Create `tests/views_spec.lua`:

```lua
-- Resolving a view name against the two sources, and what a name in neither
-- costs.

local views = require("damnit.views")
local damnit = require("damnit")

---@param declared table<string, string>
---@param run fun(notifications: string[])
local function with_views(declared, run)
  damnit.options.views = declared

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local ok, err = pcall(run, notifications)

  vim.notify = real
  damnit.options.views = {}

  assert(ok, err)
end

return {
  ["means every open task when it is given no name"] = function()
    local spec = views.resolve(nil)

    assert(spec.title == "all open tasks", spec.title)
    assert(spec.query == nil, tostring(spec.query))
    assert(vim.deep_equal(views.query_args(spec), { "ls", "--json" }), vim.inspect(views.query_args(spec)))
  end,

  ["sends the declared query rather than the name"] = function()
    with_views({ today = "due:today | overdue" }, function()
      local spec = views.resolve("today")

      assert(spec.query == "due:today | overdue", spec.query)
      assert(spec.probing == nil, "a declared view is not a probe")
      assert(vim.deep_equal(views.query_args(spec), { "ls", "due:today | overdue", "--json" }))
    end)
  end,

  ["hands an undeclared name to dam as a bare word, once"] = function()
    with_views({ today = "due:today" }, function()
      local spec = views.resolve("work")

      assert(spec.query == "work", spec.query)
      assert(spec.probing == true, "an undeclared name is a probe of dam's saved filters")
    end)
  end,

  ["refuses the name before any call once dam has refused it too"] = function()
    with_views({ today = "due:today", work = "path:work/" }, function(notifications)
      views.forget_filter("tomorrow")

      assert(views.resolve("tomorrow") == nil, "a name in neither source is refused")
      assert(#notifications == 1, vim.inspect(notifications))
      assert(notifications[1]:find('no view named "tomorrow"', 1, true), notifications[1])
      assert(notifications[1]:find("declared views are today, work", 1, true), notifications[1])
    end)
  end,

  ["says so when nothing is declared at all"] = function()
    with_views({}, function(notifications)
      views.forget_filter("today")
      views.resolve("today")

      assert(notifications[1]:find("no views are declared in setup", 1, true), notifications[1])
    end)
  end,
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua views_spec`
Expected: five FAILs, `module 'damnit.views' not found`.

- [ ] **Step 3: Write the module**

Create `lua/damnit/views.lua`:

```lua
-- A view is a name and a dam query.
--
-- Two sources, merged, with this plugin's own table winning a collision: the
-- `views` option, and dam's saved filters, which dam resolves when `dam ls` is
-- given a bare word. A name declared in dam's own config therefore works in the
-- editor, in a terminal and in a herdr pane with one declaration.

local M = {}

local message = require("damnit.message")

---@class damnit.ListSpec
---@field title string what the buffer's first line calls it
---@field query string? the dam query, or nil for every open task
---@field probing boolean? true when the query is a bare name dam has yet to judge

--- Names dam refused this session, so the second attempt costs no call.
---@type table<string, boolean>
local unknown = {}

--- The view names declared in `setup`, sorted.
---@return string[]
function M.declared()
  local names = vim.tbl_keys(require("damnit").options.views or {})
  table.sort(names)

  return names
end

--- Remember that dam does not know this name either.
---@param name string
function M.forget_filter(name)
  unknown[name] = true
end

---@param name string
local function refuse(name)
  local declared = M.declared()
  local known = #declared > 0 and ("declared views are " .. table.concat(declared, ", "))
    or "no views are declared in setup"

  message.fail(("there is no view named %q. %s"):format(name, known))
end

--- The spec a view name means, or nil after saying there is no such view.
---@param name string?
---@return damnit.ListSpec?
function M.resolve(name)
  if name == nil or name == "" then
    return { title = "all open tasks" }
  end

  local query = (require("damnit").options.views or {})[name]
  if type(query) == "string" then
    return { title = name, query = query }
  end

  if unknown[name] then
    refuse(name)

    return nil
  end

  return { title = name, query = name, probing = true }
end

--- The `ls` argv tail one spec becomes.
---@param spec damnit.ListSpec
---@return string[]
function M.query_args(spec)
  if spec.query == nil or spec.query == "" then
    return { "ls", "--json" }
  end

  return { "ls", spec.query, "--json" }
end

return M
```

- [ ] **Step 4: Run it and watch it pass**

Run: `nvim --headless --clean -l tests/run.lua views_spec`
Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

```bash
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: resolve a view name against the options and dam's saved filters"
```

---

### Task 7: The status model

One `dam status --json` document into the window's model. Pure: no Neovim API beyond the data
functions, which is what lets the window be tested without a window.

**Files:**

- Create: `lua/damnit/status_model.lua`, `tests/status_model_spec.lua`
- Create: `tests/fixtures/full/status.json`, `tests/fixtures/full/remote.json`

**Interfaces:**

- Consumes: nothing. This module is pure.
- Produces:
  - `status_model.build(status, remotes) -> damnit.Model` where
    `damnit.Model = { sections: damnit.Section[], empty: boolean, remotes: damnit.RemoteLine[] }`,
    `damnit.Section = { name: string, kind: string, entries: table[] }`.
  - Entry shapes, each carrying its own `kind`:
    `{ kind = "change", oid, op, verb, subject, path, fields, before, after }`,
    `{ kind = "conflict", oid, remote, subject, ours, theirs }`,
    `{ kind = "remote", remote, commits }`,
    `{ kind = "notice", notice_kind, text }`.
  - `status_model.changed_fields(before, after) -> string[]`
  - `status_model.FIELDS`, `.TASK_FIELDS`, `.EVENT_FIELDS`, `.VERBS`

- [ ] **Step 1: Capture the fixtures**

`tests/fixtures/full/status.json` is a status with every section populated. Write it by hand from the
shapes in section 3 of the spec, then check it against the real binary once `dam` is installed:
`dam status --json | jq .` on a scratch store, and correct any field this fixture invents.

```json
{
  "staged": [
    {
      "oid": "660a08d0a1f74c9a3c2e5d8b7f1049ab6c3d2e51",
      "op": "create",
      "before": null,
      "after": {
        "oid": "660a08d0a1f74c9a3c2e5d8b7f1049ab6c3d2e51",
        "kind": "task",
        "subject": "write the spec",
        "body": "",
        "path": "work/",
        "labels": [],
        "depends": [],
        "reminders": [],
        "task": { "done": false, "priority": 2 }
      }
    }
  ],
  "unstaged": [
    {
      "oid": "78b8950b02735107aa608659dcf19f6f50adfeb1",
      "op": "update",
      "before": {
        "oid": "78b8950b02735107aa608659dcf19f6f50adfeb1",
        "kind": "task",
        "subject": "oat milk",
        "body": "",
        "path": "inbox/",
        "labels": ["home"],
        "depends": [],
        "reminders": [],
        "task": { "done": false, "priority": 1 }
      },
      "after": {
        "oid": "78b8950b02735107aa608659dcf19f6f50adfeb1",
        "kind": "task",
        "subject": "buy oat milk",
        "body": "",
        "path": "inbox/",
        "labels": ["errand", "home"],
        "depends": [],
        "reminders": [],
        "task": { "done": false, "priority": 1, "due": "2026-09-25" }
      }
    },
    {
      "oid": "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77",
      "op": "delete",
      "before": {
        "oid": "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77",
        "kind": "task",
        "subject": "child",
        "body": "",
        "path": "work/proj/",
        "labels": [],
        "depends": [],
        "reminders": [],
        "task": { "done": false, "priority": 4 }
      },
      "after": null
    }
  ],
  "conflicts": [
    {
      "oid": "7257572f1a0c4b3e9d8a6f2b5c1e7d0a3f4b6c8e",
      "remote": "todoist",
      "ours": {
        "oid": "7257572f1a0c4b3e9d8a6f2b5c1e7d0a3f4b6c8e",
        "kind": "task",
        "subject": "file taxes here",
        "body": "",
        "path": "home/finances/",
        "labels": [],
        "depends": [],
        "reminders": [],
        "task": { "done": false, "priority": 1 }
      },
      "theirs": {
        "oid": "7257572f1a0c4b3e9d8a6f2b5c1e7d0a3f4b6c8e",
        "kind": "task",
        "subject": "file taxes there",
        "body": "",
        "path": "home/finances/",
        "labels": [],
        "depends": [],
        "reminders": [],
        "task": { "done": false, "priority": 1 }
      }
    }
  ],
  "notices": [
    { "kind": "removed_upstream", "remote": "todoist", "oid": "c1d2e3f405162738495a6b7c8d9e0f1a2b3c4d5e" }
  ],
  "unpushed": [{ "remote": "todoist", "commits": 1 }]
}
```

`tests/fixtures/full/remote.json`:

```json
{"remotes": [{"remote": "todoist", "helper": "dam-remote-todoist", "url": "todoist::", "stale_seconds": 300}]}
```

- [ ] **Step 2: Write the failing test**

Create `tests/status_model_spec.lua`:

```lua
-- One status document into the window's model, and the field summary the window
-- draws in parentheses.

local status_model = require("damnit.status_model")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

---@param name string
---@return table
local function fixture(name)
  local file = assert(io.open(("%s/fixtures/%s"):format(TESTS_DIR, name), "r"))
  local text = file:read("*a")
  file:close()

  return vim.json.decode(text, { luanil = { object = true } })
end

---@param model damnit.Model
---@param kind string
---@return damnit.Section?
local function section(model, kind)
  for _, candidate in ipairs(model.sections) do
    if candidate.kind == kind then
      return candidate
    end
  end

  return nil
end

return {
  ["renders nothing but a sentence for a status with nothing in it"] = function()
    local model = status_model.build(fixture("default/status.json"), nil)

    assert(model.empty == true, vim.inspect(model))
    assert(#model.sections == 0, vim.inspect(model.sections))
  end,

  ["puts conflicts first, because they are the only section that blocks a pull"] = function()
    local model = status_model.build(fixture("full/status.json"), fixture("full/remote.json"))

    assert(model.sections[1].kind == "conflicts", model.sections[1].kind)
    assert(model.empty == false)
  end,

  ["orders the rest working, staged, unpushed, notices"] = function()
    local model = status_model.build(fixture("full/status.json"), fixture("full/remote.json"))
    local kinds = vim.tbl_map(function(each)
      return each.kind
    end, model.sections)

    assert(vim.deep_equal(kinds, { "conflicts", "working", "staged", "unpushed", "notices" }), vim.inspect(kinds))
  end,

  ["names an update's changed fields in dam's own order"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)
    local change = section(model, "working").entries[1]

    assert(change.verb == "changed", change.verb)
    assert(change.oid == "78b8950b02735107aa608659dcf19f6f50adfeb1", change.oid)
    assert(vim.deep_equal(change.fields, { "subject", "labels", "due" }), vim.inspect(change.fields))
  end,

  ["leaves the field list empty on a create and on a delete"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)

    assert(#section(model, "staged").entries[1].fields == 0)
    assert(section(model, "staged").entries[1].verb == "new")
    assert(section(model, "working").entries[2].verb == "removed")
  end,

  ["names every field dam's own changed_fields names"] = function()
    local function moved(before, after)
      return status_model.changed_fields(before, after)
    end

    assert(vim.deep_equal(moved({ subject = "a" }, { subject = "b" }), { "subject" }))
    assert(vim.deep_equal(moved({ body = "" }, { body = "x" }), { "body" }))
    assert(vim.deep_equal(moved({ path = "a/" }, { path = "b/" }), { "path" }))
    assert(vim.deep_equal(moved({ labels = { "a" } }, { labels = { "a", "b" } }), { "labels" }))
    assert(vim.deep_equal(moved({ depends = {} }, { depends = { "78b8950" } }), { "depends" }))
    assert(vim.deep_equal(moved({ reminders = {} }, { reminders = { "2026-09-25" } }), { "reminders" }))
    assert(vim.deep_equal(moved({ recurrence = nil }, { recurrence = "weekly" }), { "recurrence" }))
    assert(vim.deep_equal(moved({ task = { priority = 1 } }, { task = { priority = 2 } }), { "priority" }))
    assert(vim.deep_equal(moved({ task = { done = false } }, { task = { done = true } }), { "done" }))
    assert(vim.deep_equal(moved({ task = {} }, { task = { due = "2026-09-25" } }), { "due" }))
    assert(vim.deep_equal(moved({ task = {} }, { task = { deadline = "2026-09-30" } }), { "deadline" }))
    assert(vim.deep_equal(moved({ event = { start = "09:00" } }, { event = { start = "10:00" } }), { "start" }))
  end,

  ["carries a remote's unpushed count beside its name"] = function()
    local model = status_model.build(fixture("full/status.json"), fixture("full/remote.json"))

    assert(vim.deep_equal(model.remotes, { { remote = "todoist", commits = 1 } }), vim.inspect(model.remotes))
  end,

  ["builds a notice line out of the fields the notice actually carries"] = function()
    local model = status_model.build(fixture("full/status.json"), nil)
    local notice = section(model, "notices").entries[1]

    assert(notice.text == "todoist: c1d2e3f removed upstream", notice.text)
  end,
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua status_model_spec`
Expected: eight FAILs, `module 'damnit.status_model' not found`.

- [ ] **Step 4: Write the module**

Create `lua/damnit/status_model.lua`:

```lua
-- One `dam status --json` document into the window's model.
--
-- Pure: nothing here touches a buffer, a window or a notification, which is
-- what makes the window's shape testable without a window.

local M = {}

--- The order dam's own `changed_fields` reports in.
M.FIELDS = { "subject", "body", "path", "labels", "depends", "reminders", "recurrence" }
M.TASK_FIELDS = { "done", "priority", "due", "deadline" }
M.EVENT_FIELDS = { "start", "end", "timezone", "location", "transparency" }

--- dam's own three verbs for the three ops.
M.VERBS = { create = "new", update = "changed", delete = "removed" }

--- One sentence per notice kind. A notice carries its own fields beyond `kind`,
--- and the line is built from whichever of them are present.
local NOTICES = {
  removed_upstream = "removed upstream",
  event_cancelled = "cancelled upstream",
  push_failed = "push failed",
  pull_failed = "pull failed",
  kind_changed = "kind changed upstream",
}

---@param value any
---@return any
local function present(value)
  if value == nil or value == vim.NIL then
    return nil
  end

  return value
end

---@param left any
---@param right any
---@return boolean
local function same(left, right)
  left, right = present(left), present(right)

  if type(left) == "table" or type(right) == "table" then
    return vim.deep_equal(left, right)
  end

  return left == right
end

--- The field names that differ between two wire objects, in dam's order.
---@param before table?
---@param after table?
---@return string[]
function M.changed_fields(before, after)
  before, after = before or {}, after or {}
  local names = {}

  for _, name in ipairs(M.FIELDS) do
    if not same(before[name], after[name]) then
      names[#names + 1] = name
    end
  end

  for _, group in ipairs({ { "task", M.TASK_FIELDS }, { "event", M.EVENT_FIELDS } }) do
    local left = present(before[group[1]]) or {}
    local right = present(after[group[1]]) or {}

    for _, name in ipairs(group[2]) do
      if not same(left[name], right[name]) then
        names[#names + 1] = name
      end
    end
  end

  return names
end

---@param change table
---@return table entry
local function change_entry(change)
  local object = present(change.after) or present(change.before) or {}
  local fields = change.op == "update" and M.changed_fields(change.before, change.after) or {}

  return {
    kind = "change",
    oid = change.oid,
    op = change.op,
    verb = M.VERBS[change.op] or change.op,
    subject = tostring(object.subject or ""),
    path = tostring(object.path or ""),
    fields = fields,
    before = present(change.before),
    after = present(change.after),
  }
end

---@param conflict table
---@return table entry
local function conflict_entry(conflict)
  local ours = present(conflict.ours) or {}

  return {
    kind = "conflict",
    oid = conflict.oid,
    remote = conflict.remote,
    subject = tostring(ours.subject or ""),
    ours = present(conflict.ours),
    theirs = present(conflict.theirs),
  }
end

--- One notice as a line, built from the fields it carries rather than from a
--- shape assumed per kind.
---@param notice table
---@return string
function M.notice_text(notice)
  local parts = {}

  if type(notice.remote) == "string" then
    parts[#parts + 1] = notice.remote .. ":"
  end

  if type(notice.oid) == "string" then
    parts[#parts + 1] = notice.oid:sub(1, 7)
  end

  parts[#parts + 1] = NOTICES[notice.kind] or tostring(notice.kind)

  for _, extra in ipairs({ "why", "reason", "detail" }) do
    if type(notice[extra]) == "string" then
      parts[#parts + 1] = notice[extra]
    end
  end

  return table.concat(parts, " ")
end

---@param name string
---@param kind string
---@param source table[]?
---@param make fun(item: table): table
---@return damnit.Section?
local function section(name, kind, source, make)
  local items = source or {}
  if #items == 0 then
    return nil
  end

  return { name = name, kind = kind, entries = vim.tbl_map(make, items) }
end

---@class damnit.Section
---@field name string the heading as it is drawn
---@field kind "conflicts"|"working"|"staged"|"unpushed"|"notices"
---@field entries table[]

---@class damnit.Model
---@field sections damnit.Section[] in the order they are drawn
---@field empty boolean true when no section has an entry
---@field remotes { remote: string, commits: integer }[]

--- The window's model for one status document.
---
--- Conflicts are drawn first because they are the only section that blocks a
--- pull. An empty section is left out entirely, the way `dam status` leaves it
--- out.
---@param status table the decoded `dam status --json`
---@param remotes table? the decoded `dam remote list --json`
---@return damnit.Model
function M.build(status, remotes)
  status = status or {}

  local counts = {}
  for _, entry in ipairs(status.unpushed or {}) do
    counts[entry.remote] = entry.commits
  end

  local listed = {}
  for _, entry in ipairs((remotes or {}).remotes or {}) do
    listed[#listed + 1] = { remote = entry.remote, commits = counts[entry.remote] or 0 }
  end

  if #listed == 0 then
    for _, entry in ipairs(status.unpushed or {}) do
      listed[#listed + 1] = { remote = entry.remote, commits = entry.commits }
    end
  end

  local sections = {}
  for _, built in ipairs({
    section("Conflicts", "conflicts", status.conflicts, conflict_entry),
    section("Working", "working", status.unstaged, change_entry),
    section("Staged", "staged", status.staged, change_entry),
    section("Unpushed", "unpushed", status.unpushed, function(item)
      return { kind = "remote", remote = item.remote, commits = item.commits }
    end),
    section("Notices", "notices", status.notices, function(item)
      return { kind = "notice", notice_kind = item.kind, text = M.notice_text(item) }
    end),
  }) do
    sections[#sections + 1] = built
  end

  return { sections = sections, empty = #sections == 0, remotes = listed }
end

return M
```

- [ ] **Step 5: Run it and watch it pass**

Run: `nvim --headless --clean -l tests/run.lua status_model_spec`
Expected: `8 passed, 0 failed`.

- [ ] **Step 6: Prove the module is pure**

Run: `grep -nE 'vim\.(api|fn|system|notify|schedule)' lua/damnit/status_model.lua`
Expected: no output.

- [ ] **Step 7: Lint and commit**

```bash
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: model a dam status document for the staging window"
```

---

### Task 8: The renderer

A model into lines and extmark specs. `render.lines` is a pure function of a model and a small state
table, which is what a golden test compares. Highlight groups link to standard groups, so a colourscheme
styles the window with no integration on its side.

**Files:**

- Create: `lua/damnit/render.lua`, `tests/render_spec.lua`, `tests/golden/*.txt`

**Interfaces:**

- Consumes: `status_model.build`.
- Produces:
  - `render.lines(model, state) -> damnit.Line[]` where
    `state = { store: string, running: { label, elapsed, pending }? }` and
    `damnit.Line = { text: string, kind: string, oid: string?, marks: { col, length, group }[] }`.
  - `render.draw(buf, lines)`, which writes the lines, clears and reapplies the marks, and records
    each line's kind in `vim.b[buf].damnit_kinds` for the fold expression.
  - `render.define()`, `render.NAMESPACE`, `render.HIGHLIGHTS`, `render.COLUMNS`, `render.icon(kind)`.

- [ ] **Step 1: Write the failing test**

Create `tests/render_spec.lua`:

```lua
-- What the window looks like, compared whole against a golden file.
--
-- A one-character change to a rendering is then a diff a reviewer can read.
-- Regenerate every golden with DAMNIT_GOLDEN_UPDATE=1 and read the diff before
-- committing it.

local render = require("damnit.render")
local status_model = require("damnit.status_model")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

---@param name string
---@return table
local function fixture(name)
  local file = assert(io.open(("%s/fixtures/%s"):format(TESTS_DIR, name), "r"))
  local text = file:read("*a")
  file:close()

  return vim.json.decode(text, { luanil = { object = true } })
end

--- One status holding only the named sections, so nine window states come from
--- one fixture rather than from nine.
---@param ... string
---@return table
local function only(...)
  local full = fixture("full/status.json")
  local kept = { staged = {}, unstaged = {}, conflicts = {}, notices = {}, unpushed = {} }

  for _, name in ipairs({ ... }) do
    kept[name] = full[name]
  end

  return kept
end

local STATE = { store = "~/.local/share/dam/dam.db" }

---@param name string
---@param lines damnit.Line[]
local function golden(name, lines)
  local path = ("%s/golden/%s.txt"):format(TESTS_DIR, name)
  local text = table.concat(
    vim.tbl_map(function(line)
      return line.text
    end, lines),
    "\n"
  ) .. "\n"

  if vim.env.DAMNIT_GOLDEN_UPDATE == "1" then
    vim.fn.mkdir(("%s/golden"):format(TESTS_DIR), "p")
    local out = assert(io.open(path, "w"))
    out:write(text)
    out:close()

    return
  end

  local file = assert(io.open(path, "r"), "no golden at " .. path .. "; regenerate with DAMNIT_GOLDEN_UPDATE=1")
  local want = file:read("*a")
  file:close()

  assert(text == want, ("golden %s differs\n--- got ---\n%s--- want ---\n%s"):format(name, text, want))
end

---@param status table
---@param state table?
---@return damnit.Line[]
local function lines_of(status, state)
  return render.lines(status_model.build(status, fixture("full/remote.json")), state or STATE)
end

return {
  ["draws an empty store as dam's own sentence"] = function()
    local lines = lines_of(fixture("default/status.json"))
    golden("empty", lines)

    assert(lines[#lines].text == "nothing staged, nothing changed", lines[#lines].text)
  end,

  ["draws each section on its own"] = function()
    golden("working", lines_of(only("unstaged")))
    golden("staged", lines_of(only("staged")))
    golden("unpushed", lines_of(only("unpushed")))
    golden("notices", lines_of(only("notices")))
    golden("conflicts", lines_of(only("conflicts")))
  end,

  ["draws every section at once, conflicts first"] = function()
    golden("full", lines_of(fixture("full/status.json")))
  end,

  ["puts the running operation and its elapsed time in the header"] = function()
    local state = {
      store = STATE.store,
      running = { label = "push todoist", elapsed = 12.34, pending = 2 },
    }
    local lines = lines_of(fixture("full/status.json"), state)
    golden("running", lines)

    assert(lines[3].text:find("push todoist", 1, true), lines[3].text)
    assert(lines[3].text:find("12.3s", 1, true), lines[3].text)
    assert(lines[3].text:find("(2 queued)", 1, true), lines[3].text)
  end,

  ["marks the verb, the oid and the path with their own groups"] = function()
    local lines = lines_of(only("unstaged"))

    local change = nil
    for _, line in ipairs(lines) do
      if line.kind == "change" then
        change = line
        break
      end
    end

    local groups = vim.tbl_map(function(mark)
      return mark.group
    end, change.marks)

    assert(vim.tbl_contains(groups, "DamOpChanged"), vim.inspect(groups))
    assert(vim.tbl_contains(groups, "DamOid"), vim.inspect(groups))
    assert(vim.tbl_contains(groups, "DamPath"), vim.inspect(groups))
    assert(change.oid == "78b8950b02735107aa608659dcf19f6f50adfeb1", tostring(change.oid))
  end,

  ["links every group to a standard one and writes no colour"] = function()
    for group, target in pairs(render.HIGHLIGHTS) do
      assert(type(target) == "string" and target ~= "", group)
    end

    render.define()

    local defined = vim.api.nvim_get_hl(0, { name = "DamOverdue", link = true })
    assert(defined.link == "ErrorMsg", vim.inspect(defined))
  end,
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua render_spec`
Expected: every case FAILs with `module 'damnit.render' not found`.

- [ ] **Step 3: Write the module**

Create `lua/damnit/render.lua`:

```lua
-- A model into lines and extmark specs.
--
-- This module knows nothing about dam. It takes a model and hands back lines,
-- each carrying the marks that colour it, so a golden test compares a rendering
-- without opening a window.

local M = {}

M.NAMESPACE = vim.api.nvim_create_namespace("damnit")

--- The display column each field of a change line starts at.
M.COLUMNS = { verb = 2, oid = 11, subject = 20, fields = 48, path = 72 }

--- Every group, and the standard group it links to. No colour is written here,
--- so a colourscheme styles the window with nothing on its side.
M.HIGHLIGHTS = {
  DamHeader = "Title",
  DamSection = "Statement",
  DamOpNew = "DiffAdd",
  DamOpChanged = "DiffChange",
  DamOpRemoved = "DiffDelete",
  DamOid = "Identifier",
  DamSubject = "Normal",
  DamPath = "Directory",
  DamFields = "Comment",
  DamLabel = "Tag",
  DamDue = "Constant",
  DamOverdue = "ErrorMsg",
  DamPriority1 = "ErrorMsg",
  DamPriority2 = "WarningMsg",
  DamPriority3 = "MoreMsg",
  DamPriority4 = "Comment",
  DamRemote = "Special",
  DamNotice = "WarningMsg",
  DamConflict = "ErrorMsg",
  DamDiffOld = "DiffDelete",
  DamDiffNew = "DiffAdd",
  DamRunning = "MoreMsg",
}

local OP_GROUPS = { create = "DamOpNew", update = "DamOpChanged", delete = "DamOpRemoved" }

--- One ASCII column each, so the rendering is the same width whether or not
--- mini.icons is installed.
local FALLBACKS = { task = "-", event = "@", remote = ">", conflict = "!" }
local MINI = { task = { "default", "file" }, event = { "default", "calendar" }, remote = { "default", "git" }, conflict = { "default", "error" } }

--- Declare every group. Called once when the first window opens.
function M.define()
  for group, target in pairs(M.HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

--- mini.icons when it is loaded, the ASCII fallback when it is not. Looked up
--- at render time rather than required at load.
---@param kind string
---@return string
function M.icon(kind)
  local ok, icons = pcall(require, "mini.icons")
  if not ok then
    return FALLBACKS[kind] or "-"
  end

  local args = MINI[kind] or MINI.task
  local glyph = icons.get(args[1], args[2])

  return (type(glyph) == "string" and glyph ~= "" and glyph) or FALLBACKS[kind] or "-"
end

--- A line under construction. `add` appends a segment, records its mark and
--- pads out to a display column, so a subject holding wide characters does not
--- shift the columns after it.
local function row()
  local parts, marks, bytes, display = {}, {}, 0, 0

  local function add(text, group, column)
    text = tostring(text)

    if group and #text > 0 then
      marks[#marks + 1] = { col = bytes, length = #text, group = group }
    end

    parts[#parts + 1] = text
    bytes = bytes + #text
    display = display + vim.fn.strdisplaywidth(text)

    if column and display < column then
      local fill = (" "):rep(column - display)
      parts[#parts + 1] = fill
      bytes = bytes + #fill
      display = column
    end
  end

  return {
    add = add,
    line = function(kind, oid)
      return { text = (table.concat(parts):gsub("%s+$", "")), kind = kind, oid = oid, marks = marks }
    end,
  }
end

---@return damnit.Line
local function blank()
  return { text = "", kind = "blank", marks = {} }
end

---@param label string
---@param value string
---@param group string?
---@return damnit.Line
local function header_line(label, value, group)
  local built = row()
  built.add(label, "DamHeader", 9)
  built.add(value, group)

  return built.line("header")
end

---@param remotes { remote: string, commits: integer }[]
---@return damnit.Line
local function remotes_line(remotes)
  if #remotes == 0 then
    return header_line("Remotes:", "none configured")
  end

  local built = row()
  built.add("Remotes:", "DamHeader", 9)

  for index, remote in ipairs(remotes) do
    if index > 1 then
      built.add("  ")
    end

    built.add(remote.remote, "DamRemote")
    built.add(remote.commits > 0 and (" (%d unpushed)"):format(remote.commits) or " (clean)")
  end

  return built.line("header")
end

---@param running { label: string, elapsed: number, pending: integer }
---@return damnit.Line
local function running_line(running)
  local built = row()
  built.add("Running:", "DamHeader", 9)
  built.add(("%s  %.1fs"):format(running.label, running.elapsed), "DamRunning")

  if running.pending > 0 then
    built.add(("  (%d queued)"):format(running.pending))
  end

  built.add("     [C-c to cancel]")

  return built.line("header")
end

---@param section damnit.Section
---@return damnit.Line
local function section_line(section)
  local built = row()
  built.add(("%s (%d)"):format(section.name, #section.entries), "DamSection")

  return built.line("section")
end

---@param entry table
---@return damnit.Line
local function change_line(entry)
  local object = entry.after or entry.before or {}
  local built = row()

  built.add(M.icon(object.kind or "task"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.verb, OP_GROUPS[entry.op], M.COLUMNS.oid)
  built.add(entry.oid:sub(1, 7), "DamOid", M.COLUMNS.subject)
  built.add(entry.subject, "DamSubject", M.COLUMNS.fields)

  if #entry.fields > 0 then
    built.add("(" .. table.concat(entry.fields, ", ") .. ")", "DamFields", M.COLUMNS.path)
  else
    built.add("", nil, M.COLUMNS.path)
  end

  built.add(entry.path, "DamPath")

  return built.line("change", entry.oid)
end

---@param entry table
---@return damnit.Line
local function remote_line(entry)
  local built = row()
  built.add(M.icon("remote"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.remote, "DamRemote", M.COLUMNS.subject)
  built.add(("%d unpushed"):format(entry.commits))

  return built.line("remote")
end

---@param entry table
---@return damnit.Line
local function conflict_line(entry)
  local built = row()
  built.add(M.icon("conflict"))
  built.add(" ", nil, M.COLUMNS.verb)
  built.add(entry.oid:sub(1, 7), "DamOid", M.COLUMNS.subject)
  built.add(entry.subject, "DamConflict", M.COLUMNS.fields)
  built.add(entry.remote, "DamRemote")

  return built.line("conflict", entry.oid)
end

---@param entry table
---@return damnit.Line
local function notice_line(entry)
  local built = row()
  built.add("  ")
  built.add(entry.text, "DamNotice")

  return built.line("notice")
end

local ENTRY_LINES = {
  change = change_line,
  remote = remote_line,
  conflict = conflict_line,
  notice = notice_line,
}

--- The lines one model becomes.
---@param model damnit.Model
---@param state { store: string, running: { label: string, elapsed: number, pending: integer }? }
---@return damnit.Line[]
function M.lines(model, state)
  local lines = { header_line("Store:", state.store), remotes_line(model.remotes) }

  if state.running then
    lines[#lines + 1] = running_line(state.running)
  end

  lines[#lines + 1] = header_line("Help:", "g?")
  lines[#lines + 1] = blank()

  if model.empty then
    lines[#lines + 1] = { text = "nothing staged, nothing changed", kind = "empty", marks = {} }

    return lines
  end

  for _, section in ipairs(model.sections) do
    lines[#lines + 1] = section_line(section)

    for _, entry in ipairs(section.entries) do
      lines[#lines + 1] = ENTRY_LINES[entry.kind](entry)
    end

    lines[#lines + 1] = blank()
  end

  return lines
end

--- Put the lines in a buffer and colour them.
---
--- The buffer is unmodifiable, so the write is bracketed. Every mark is cleared
--- and reapplied, because the whole buffer is redrawn rather than patched.
---@param buf integer
---@param lines damnit.Line[]
function M.draw(buf, lines)
  local text, kinds, oids = {}, {}, {}

  for index, line in ipairs(lines) do
    text[index] = line.text
    kinds[index] = line.kind
    oids[index] = line.oid
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, M.NAMESPACE, 0, -1)

  for index, line in ipairs(lines) do
    for _, mark in ipairs(line.marks) do
      vim.api.nvim_buf_set_extmark(buf, M.NAMESPACE, index - 1, mark.col, {
        end_col = mark.col + mark.length,
        hl_group = mark.group,
      })
    end
  end

  vim.b[buf].damnit_kinds = kinds
  vim.b[buf].damnit_oids = oids
end

return M
```

- [ ] **Step 4: Generate the goldens and read them**

```bash
DAMNIT_GOLDEN_UPDATE=1 nvim --headless --clean -l tests/run.lua render_spec
git diff --stat tests/golden
cat tests/golden/full.txt
```

Expected: eight files under `tests/golden/`. Read `full.txt` against section 4 of the spec: the four
header lines, `Conflicts` first, then `Working`, `Staged`, `Unpushed`, `Notices`, and a change line
reading `- changed  78b8950  buy oat milk  (subject, labels, due)  inbox/` with the columns aligned. Fix
the renderer rather than the golden when they disagree.

- [ ] **Step 5: Run it again without the update flag**

Run: `nvim --headless --clean -l tests/run.lua render_spec`
Expected: `6 passed, 0 failed`.

- [ ] **Step 6: Lint and commit**

```bash
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: render the staging window's model as lines and extmarks"
```

---

### Task 9: The status window, the command, and the navigation keys

`:Dam` opens one buffer per store, re-read in full from a fresh `dam status --json`. This task also
lands the key table every later key hangs off, the folds, `R`, `q`, `g?`, the five section jumps and
`:Dam cancel`.

**Files:**

- Create: `lua/damnit/window.lua`, `lua/damnit/keys.lua`, `lua/damnit/actions.lua`,
  `plugin/damnit.lua`, `tests/window_spec.lua`
- Modify: `lua/damnit/render.lua` (tag each line with its section kind)
- Modify: `lua/damnit/init.lua` (`M.open_status`)

**Interfaces:**

- Consumes: `queue.submit`, `queue.running`, `queue.cancel`, `queue.on_tick`, `render.lines`,
  `render.draw`, `status_model.build`.
- Produces:
  - `window.open() -> integer buf`, `window.refresh(key?)`, `window.tick(key)`,
    `window.model(key?) -> damnit.Model?`, `window.buffer(key?) -> integer?`,
    `window.entry_under_cursor() -> table?`, `window.line_of(section_kind, nth) -> integer?`,
    `window.origin() -> integer?` (the window `:Dam` was opened from).
  - `keys.MAPS` keyed by filetype, each row `{ mode, lhs, rhs, desc }`; `keys.attach(buf, filetype)`.
  - `actions.jump_to_section(kind, name, count)`, `actions.help(filetype)`, `actions.close()`.
  - `SUBCOMMANDS` in `plugin/damnit.lua`, one row per `:Dam` subcommand, which later tasks add to.

- [ ] **Step 1: Tag each rendered line with its section**

In `lua/damnit/render.lua`, inside `M.lines`, set the section kind on every line a section owns:

```lua
  for _, section in ipairs(model.sections) do
    local heading = section_line(section)
    heading.section = section.kind
    lines[#lines + 1] = heading

    for _, entry in ipairs(section.entries) do
      local line = ENTRY_LINES[entry.kind](entry)
      line.section = section.kind
      lines[#lines + 1] = line
    end

    lines[#lines + 1] = blank()
  end
```

And in `M.draw`, record them beside the kinds:

```lua
  local text, kinds, oids, sections = {}, {}, {}, {}

  for index, line in ipairs(lines) do
    text[index] = line.text
    kinds[index] = line.kind
    oids[index] = line.oid
    sections[index] = line.section
  end
```

```lua
  vim.b[buf].damnit_sections = sections
```

- [ ] **Step 2: Write the failing test**

Create `tests/window_spec.lua`:

```lua
-- The status window: one per store, re-read rather than patched, and the keys
-- that move around it.

dofile(((arg[0]:match("(.*)/") or ".") .. "/../plugin/damnit.lua"))

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local window = require("damnit.window")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

---@param run fun(fake: damnit.FakeDam, notifications: string[])
---@param fixtures string?
local function with_window(run, fixtures)
  local fake = fake_dam.install({ fixtures = fixtures or (TESTS_DIR .. "/fixtures/full") })
  queue.reset()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local buf = window.open()
  fake_dam.settle(function()
    return queue.running() == nil and vim.api.nvim_buf_line_count(buf) > 1
  end)

  local ok, err = pcall(run, fake, notifications)

  vim.notify = real
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

return {
  ["opens one buffer per store and focuses it rather than opening a second"] = function()
    with_window(function()
      local first = window.buffer()
      vim.cmd("wincmd p")
      local second = window.open()

      assert(first == second, "a second :Dam focuses the buffer the first opened")

      local shown = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == first then
          shown = shown + 1
        end
      end
      assert(shown == 1, ("the buffer is in %d windows"):format(shown))
    end)
  end,

  ["makes the buffer unmodifiable, unlisted and scratch"] = function()
    with_window(function()
      local buf = window.buffer()

      assert(vim.bo[buf].filetype == "damstatus", vim.bo[buf].filetype)
      assert(vim.bo[buf].buftype == "nofile", vim.bo[buf].buftype)
      assert(vim.bo[buf].bufhidden == "hide", vim.bo[buf].bufhidden)
      assert(vim.bo[buf].modifiable == false)
      assert(vim.bo[buf].buflisted == false)
      assert(vim.bo[buf].swapfile == false)
    end)
  end,

  ["reads the status from dam rather than guessing at it"] = function()
    with_window(function(fake)
      local log = fake_dam.argv_log(fake)

      assert(vim.tbl_contains(log, "status --json"), vim.inspect(log))
      assert(vim.tbl_contains(log, "remote list --json"), vim.inspect(log))
      assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("Store:", 1, true), "the header is drawn")
    end)
  end,

  ["R reads the status again"] = function()
    with_window(function(fake)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("R", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "status --json", vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["gu, gs and gc jump to a section, and a count picks the entry"] = function()
    with_window(function()
      vim.api.nvim_feedkeys("gu", "x", false)
      local unstaged = vim.api.nvim_win_get_cursor(0)[1]
      assert(vim.b[0].damnit_sections[unstaged] == "working", vim.inspect(vim.b[0].damnit_sections))

      vim.api.nvim_feedkeys("2gu", "x", false)
      assert(vim.api.nvim_win_get_cursor(0)[1] == unstaged + 1, "a count picks the second entry")

      vim.api.nvim_feedkeys("gc", "x", false)
      local conflict = vim.api.nvim_win_get_cursor(0)[1]
      assert(vim.b[0].damnit_sections[conflict] == "conflicts", tostring(vim.b[0].damnit_sections[conflict]))
    end)
  end,

  ["refuses a jump to a section this status has none of"] = function()
    with_window(function(_, notifications)
      vim.api.nvim_feedkeys("gs", "x", false)

      assert(notifications[#notifications] == "damnit.nvim: no Staged section", notifications[#notifications])
    end, TESTS_DIR .. "/fixtures/default")
  end,

  ["q hides the window and keeps the buffer"] = function()
    with_window(function()
      local buf = window.buffer()
      vim.api.nvim_feedkeys("q", "x", false)

      assert(vim.api.nvim_buf_is_valid(buf), "the buffer survives, so a re-open is instant")
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        assert(vim.api.nvim_win_get_buf(win) ~= buf, "no window still shows it")
      end
    end)
  end,

  [":Dam cancel says nothing is running when nothing is"] = function()
    with_window(function(_, notifications)
      vim.cmd("Dam cancel")

      assert(notifications[#notifications] == "damnit.nvim: nothing is running", notifications[#notifications])
    end)
  end,
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua window_spec`
Expected: every case FAILs with `module 'damnit.window' not found`.

- [ ] **Step 4: Write the key table**

Create `lua/damnit/keys.lua`:

```lua
-- Every mapping in every buffer this plugin owns, one table per filetype.
--
-- The description beside each key is what `g?` shows, so the help and the
-- mappings cannot drift apart.

local M = {}

---@param name string
---@param heading string
---@return fun()
local function jump(name, heading)
  return function()
    require("damnit.actions").jump_to_section(name, heading, vim.v.count1)
  end
end

---@param fn string the name of a function on damnit.actions
---@return fun()
local function act(fn)
  return function()
    require("damnit.actions")[fn]()
  end
end

---@type table<string, { [1]: string, [2]: string, [3]: fun(), [4]: string }[]>
M.MAPS = {
  damstatus = {
    { "n", "R", act("refresh"), "re-read the status" },
    { "n", "gu", jump("working", "Working"), "jump to Working" },
    { "n", "gs", jump("staged", "Staged"), "jump to Staged" },
    { "n", "gp", jump("unpushed", "Unpushed"), "jump to Unpushed" },
    { "n", "gn", jump("notices", "Notices"), "jump to Notices" },
    { "n", "gc", jump("conflicts", "Conflicts"), "jump to Conflicts" },
    { "n", "<C-c>", act("cancel"), "cancel the running operation" },
    { "n", "q", act("close"), "close the window" },
    { "n", "gq", act("close"), "close the window" },
    {
      "n",
      "g?",
      function()
        require("damnit.actions").help("damstatus")
      end,
      "show this help",
    },
  },
}

--- Put one filetype's mappings on a buffer.
---@param buf integer
---@param filetype string
function M.attach(buf, filetype)
  for _, map in ipairs(M.MAPS[filetype] or {}) do
    vim.keymap.set(map[1], map[2], map[3], { buffer = buf, nowait = true, desc = "dam: " .. map[4] })
  end
end

return M
```

- [ ] **Step 5: Write the actions this task needs**

Create `lua/damnit/actions.lua`:

```lua
-- What each key does: read the cursor, queue the call, handle the result.

local M = {}

local message = require("damnit.message")

--- Re-read the status. Queued like anything else, so it waits behind a push.
function M.refresh()
  require("damnit.window").refresh()
end

function M.cancel()
  require("damnit.queue").cancel()
end

function M.close()
  vim.api.nvim_win_close(0, false)
end

--- Move to the count-th entry of a section, or say the section is not there.
---@param kind string
---@param heading string
---@param count integer
function M.jump_to_section(kind, heading, count)
  local line = require("damnit.window").line_of(kind, count)

  if not line then
    return message.warn(("no %s section"):format(heading))
  end

  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

--- The key table for one filetype, in a float that closes on any key.
---@param filetype string
function M.help(filetype)
  local rows = {}
  for _, map in ipairs(require("damnit.keys").MAPS[filetype] or {}) do
    rows[#rows + 1] = ("  %-8s %s"):format(map[2], map[4])
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  vim.bo[buf].modifiable = false

  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - #rows) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width + 2,
    height = #rows,
    style = "minimal",
    border = "rounded",
  })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.api.nvim_win_close, win, true)
    end,
  })
end

return M
```

- [ ] **Step 6: Write the window**

Create `lua/damnit/window.lua`:

```lua
-- Creating, finding and focusing the status window and its buffer.
--
-- One buffer per store, keyed the way the queue is keyed. The buffer is redrawn
-- in full from a fresh `dam status --json`; nothing patches it in place, so what
-- is on screen came from dam rather than from a guess at what a write did.

local M = {}

local queue = require("damnit.queue")
local render = require("damnit.render")
local status_model = require("damnit.status_model")
local message = require("damnit.message")

---@type table<string, integer>
local buffers = {}

---@type table<string, damnit.Model>
local models = {}

---@type table<string, table>
local remotes = {}

---@type table<string, table<string, boolean>>
local folded = {}

---@type integer?
local origin = nil

--- The store as the header names it. dam does not report its own default path,
--- and this plugin does not hardcode one.
---@param key string
---@return string
local function store_display(key)
  if key == "default" then
    return "dam's default"
  end

  return vim.fn.fnamemodify(key, ":~")
end

--- The fold level of one line, read off the kinds the renderer recorded.
---@param lnum integer
---@return string
function M.fold_level(lnum)
  local kind = (vim.b.damnit_kinds or {})[lnum]

  if kind == "section" then
    return ">1"
  end

  if kind == "header" or kind == "blank" or kind == "empty" then
    return "0"
  end

  return "1"
end

---@param buf integer
---@return integer? win
local function window_for(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end

  return nil
end

---@param key string
---@return integer buf
function M.buffer(key)
  key = key or queue.key()

  local existing = buffers[key]
  if existing and vim.api.nvim_buf_is_valid(existing) then
    return existing
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ("damnit://status/%s"):format(key))
  vim.bo[buf].filetype = "damstatus"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].modifiable = false

  require("damnit.keys").attach(buf, "damstatus")
  buffers[key] = buf

  return buf
end

---@param win integer
local function configure(win)
  vim.wo[win].foldmethod = "expr"
  vim.wo[win].foldexpr = "v:lua.require'damnit.window'.fold_level(v:lnum)"
  vim.wo[win].foldlevel = 99
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
end

---@param buf integer
local function open_split(buf)
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, math.max(math.floor(vim.o.lines / 3), 10))
end

---@param buf integer
local function open_float(buf)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.7)

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.win then
    snacks.win({ buf = buf, width = width, height = height, border = "rounded" })

    return
  end

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
  })
end

--- Open the status window, or focus the one this store already has.
---@return integer buf
function M.open()
  local key = queue.key()
  render.define()

  local buf = M.buffer(key)
  local win = window_for(buf)

  if win then
    vim.api.nvim_set_current_win(win)
  else
    origin = vim.api.nvim_get_current_win()

    if require("damnit").options.window.float then
      open_float(buf)
    else
      open_split(buf)
    end

    configure(vim.api.nvim_get_current_win())
  end

  M.refresh(key)

  return buf
end

--- The window `:Dam` was opened from, when it is still there.
---@return integer?
function M.origin()
  if origin and vim.api.nvim_win_is_valid(origin) then
    return origin
  end

  return nil
end

--- The model the window last drew.
---@param key string?
---@return damnit.Model?
function M.model(key)
  return models[key or queue.key()]
end

--- The buffer line the count-th entry of a section is on.
---@param section_kind string
---@param nth integer
---@return integer?
function M.line_of(section_kind, nth)
  local buf = buffers[queue.key()]
  if not buf then
    return nil
  end

  local sections = vim.b[buf].damnit_sections or {}
  local kinds = vim.b[buf].damnit_kinds or {}
  local seen = 0

  for index, owner in ipairs(sections) do
    if owner == section_kind and kinds[index] ~= "section" then
      seen = seen + 1

      if seen == nth then
        return index
      end
    end
  end

  -- A count past the end lands on the last entry, the way fugitive's jumps do.
  return seen > 0 and M.line_of(section_kind, seen) or nil
end

--- The model entry the cursor is on, with the section that holds it.
---@return { entry: table, section: damnit.Section }?
function M.entry_under_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "damstatus" then
    return nil
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}
  local model = M.model()

  if not model or kinds[lnum] == "section" or not sections[lnum] then
    return nil
  end

  for _, section in ipairs(model.sections) do
    if section.kind == sections[lnum] then
      local nth = 0

      for index = 1, lnum do
        if sections[index] == section.kind and kinds[index] ~= "section" then
          nth = nth + 1
        end
      end

      local entry = section.entries[nth]
      if entry then
        return { entry = entry, section = section }
      end
    end
  end

  return nil
end

---@param key string
---@param win integer
local function remember_folds(key, win)
  folded[key] = {}

  local buf = vim.api.nvim_win_get_buf(win)
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}

  for index, kind in ipairs(kinds) do
    if kind == "section" then
      folded[key][sections[index]] = vim.fn.foldclosed(index) ~= -1
    end
  end
end

---@param key string
---@param win integer
local function apply_folds(key, win)
  local closed = folded[key] or {}
  local buf = vim.api.nvim_win_get_buf(win)
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}

  vim.api.nvim_win_call(win, function()
    for index, kind in ipairs(kinds) do
      if kind == "section" and closed[sections[index]] then
        pcall(vim.cmd, index .. "foldclose")
      end
    end
  end)
end

---@param key string
---@param lines damnit.Line[]
local function draw(key, lines)
  local buf = buffers[key]
  local win = window_for(buf)
  local oid = nil
  local lnum = 1

  if win then
    lnum = vim.api.nvim_win_get_cursor(win)[1]
    oid = (vim.b[buf].damnit_oids or {})[lnum]
    remember_folds(key, win)
  end

  render.draw(buf, lines)

  if not win then
    return
  end

  local target = lnum
  if oid then
    for index, each in ipairs(vim.b[buf].damnit_oids or {}) do
      if each == oid then
        target = index
        break
      end
    end
  end

  local count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(win, { math.min(math.max(target, 1), count), 0 })
  apply_folds(key, win)
end

---@param key string
---@param status table
function M.redraw(key, status)
  local buf = buffers[key]
  if not buf or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  models[key] = status_model.build(status, remotes[key])

  draw(key, render.lines(models[key], { store = store_display(key), running = queue.running(key) }))
end

--- Ask dam for the status and redraw from the answer.
---@param key string?
function M.refresh(key)
  key = key or queue.key()

  if remotes[key] == nil then
    queue.submit({
      args = { "remote", "list", "--json" },
      label = "remote list",
      on_done = function(data)
        remotes[key] = data or { remotes = {} }
      end,
    })
  end

  queue.submit({
    args = { "status", "--json" },
    label = "status",
    on_done = function(status, err)
      if err then
        return message.report(err)
      end

      M.redraw(key, status)
    end,
  })
end

--- Forget the cached remote list, so the next refresh reads it again.
---@param key string?
function M.forget_remotes(key)
  remotes[key or queue.key()] = nil
end

--- Rewrite the header while something is running. One buffer, a few lines, no
--- dam call and no other buffer touched.
---@param key string
function M.tick(key)
  local buf = buffers[key]
  if not buf or not vim.api.nvim_buf_is_loaded(buf) or not models[key] then
    return
  end

  local lines = render.lines(models[key], { store = store_display(key), running = queue.running(key) })

  local headers = 0
  for _, line in ipairs(lines) do
    if line.kind ~= "header" then
      break
    end
    headers = headers + 1
  end

  local drawn = 0
  for _, kind in ipairs(vim.b[buf].damnit_kinds or {}) do
    if kind ~= "header" then
      break
    end
    drawn = drawn + 1
  end

  if headers ~= drawn then
    return draw(key, lines)
  end

  local text = {}
  for index = 1, headers do
    text[index] = lines[index].text
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, headers, false, text)
  vim.bo[buf].modifiable = false
end

queue.on_tick(M.tick)

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = vim.api.nvim_create_augroup("damnit", { clear = false }),
  pattern = "damnit://status/*",
  desc = "dam: :e re-reads the status",
  callback = function()
    M.refresh()
  end,
})

return M
```

- [ ] **Step 7: Write the user command**

Create `plugin/damnit.lua`:

```lua
-- `:Dam` and its subcommands.
--
-- Declared here rather than behind `setup` so that entering Neovim on one
-- works, which is how a herdr pane and the list buffer open an object:
-- `nvim +"Dam task <oid>"` in an editor holding nothing else.

if vim.g.loaded_damnit then
  return
end
vim.g.loaded_damnit = true

--- One entry per subcommand. `""` is `:Dam` with no argument.
---@type table<string, fun(args: string[], cmd: table)>
local SUBCOMMANDS = {
  [""] = function()
    require("damnit.window").open()
  end,
  cancel = function()
    require("damnit.queue").cancel()
  end,
}

---@return string
local function usage()
  local names = {}
  for name in pairs(SUBCOMMANDS) do
    if name ~= "" then
      names[#names + 1] = ":Dam " .. name
    end
  end
  table.sort(names)

  return "usage is :Dam, " .. table.concat(names, ", ")
end

---@param lead string
---@return string[]
local function complete(lead)
  local names = {}
  for name in pairs(SUBCOMMANDS) do
    if name ~= "" and vim.startswith(name, lead) then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  return names
end

vim.api.nvim_create_user_command("Dam", function(cmd)
  local args = cmd.fargs
  local run = SUBCOMMANDS[args[1] or ""]

  if not run then
    return vim.notify("damnit.nvim: " .. usage(), vim.log.levels.ERROR)
  end

  run(vim.list_slice(args, 2), cmd)
end, {
  nargs = "*",
  range = true,
  complete = complete,
  desc = "dam: the staging window, a list, a task, a search, the history, the sidebar or a capture",
})
```

- [ ] **Step 8: Add the keymap entry point**

In `lua/damnit/init.lua`:

```lua
--- Open the staging window, which is this plugin's default surface.
---
--- The function a keymap calls:
--- `vim.keymap.set("n", "<leader>Ts", require("damnit").open_status)`.
---@return integer buf
function M.open_status()
  return require("damnit.window").open()
end
```

- [ ] **Step 9: Run it and watch it pass**

Run: `nvim --headless --clean -l tests/run.lua window_spec`
Expected: `8 passed, 0 failed`.

- [ ] **Step 10: Run the whole suite, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua | tail -1
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: open the staging window and move around it"
```

---

### Task 10: Staging

`-`, `s`, `u` and `U`. A heading stages its whole section in one call, a visual range stages what it
covers, and the window always re-renders from a fresh status, even after a refusal.

**Files:**

- Modify: `lua/damnit/actions.lua`, `lua/damnit/keys.lua`
- Create: `tests/keys_spec.lua`

**Interfaces:**

- Produces: `actions.targets() -> { oids: string[], section: string? }`,
  `actions.stage()`, `actions.unstage()`, `actions.toggle_stage()`, `actions.unstage_all()`,
  `actions.write(args, label)`, the shared "queue it, report a failure, re-read the status" path every
  later write key uses.

- [ ] **Step 1: Write the failing test**

Create `tests/keys_spec.lua`. It reuses `with_window` from `window_spec`, so lift that helper into
`tests/helpers/status_window.lua` first and have both specs `dofile` it.

```lua
-- Every key in the status window, asserted by the argv the fake dam recorded.

local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")

return {
  ["- stages the change under the cursor"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("-", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before + 1
      end)

      local log = fake_dam.argv_log(fake)
      assert(log[before + 1] == "add 78b8950b02735107aa608659dcf19f6f50adfeb1 --json", vim.inspect(log))
      assert(log[before + 2] == "status --json", "the window re-reads rather than patching itself")
    end)
  end,

  ["- on a staged change sends reset instead"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("-", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == "reset 660a08d0a1f74c9a3c2e5d8b7f1049ab6c3d2e51 --json",
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,

  ["a heading stages every change in its section in one call"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      vim.api.nvim_feedkeys("k", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("s", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      local sent = fake_dam.argv_log(fake)[before + 1]
      assert(sent:find("^add "), sent)
      assert(sent:find("78b8950b02735107aa608659dcf19f6f50adfeb1", 1, true), sent)
      assert(sent:find("a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77", 1, true), sent)
    end)
  end,

  ["s on something already staged sends nothing and says so"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("s", "x", false)

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(notifications[#notifications] == "damnit.nvim: already staged", notifications[#notifications])
    end)
  end,

  ["staging keys do nothing on a notice or a conflict line"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("gc", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("-", "x", false)

      assert(#fake_dam.argv_log(fake) == before)
      assert(
        notifications[#notifications] == "damnit.nvim: nothing to stage on this line",
        notifications[#notifications]
      )
    end)
  end,

  ["U unstages everything, and says nothing is staged when nothing is"] = function()
    status_window.with(function(fake)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("U", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "reset --json", vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua keys_spec`
Expected: six FAILs, the first on the missing `tests/helpers/status_window.lua`.

- [ ] **Step 3: Write the staging actions**

Add to `lua/damnit/actions.lua`:

```lua
--- The objects the cursor or the visual range covers.
---
--- A section heading contributes every change in its section, which is what
--- makes `-` on a heading one call rather than one per line. A conflict or a
--- notice line contributes nothing.
---@return { oids: string[], section: string? }
function M.targets()
  local buf = vim.api.nvim_get_current_buf()
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}
  local oids = vim.b[buf].damnit_oids or {}

  local first = vim.api.nvim_win_get_cursor(0)[1]
  local last = first

  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    first, last = vim.fn.line("v"), vim.fn.line(".")

    if first > last then
      first, last = last, first
    end
  end

  local picked, seen, section = {}, {}, nil

  ---@param index integer
  local function take(index)
    local oid = oids[index]

    if oid and kinds[index] == "change" and not seen[oid] then
      seen[oid] = true
      picked[#picked + 1] = oid
      section = section or sections[index]
    end
  end

  for lnum = first, last do
    if kinds[lnum] == "section" then
      section = section or sections[lnum]

      for index, owner in ipairs(sections) do
        if owner == sections[lnum] then
          take(index)
        end
      end
    else
      take(lnum)
    end
  end

  return { oids = picked, section = section }
end

---@param verb string
---@param oids string[]
---@return string[]
local function verb_args(verb, oids)
  local args = { verb }
  vim.list_extend(args, oids)
  args[#args + 1] = "--json"

  return args
end

--- Queue one write, report a failure, and re-read the status either way.
---
--- The window shows what dam holds, never what a refused write intended.
---@param args string[]
---@param label string
function M.write(args, label)
  require("damnit.queue").submit({
    args = args,
    label = label,
    on_done = function(_, err)
      if err then
        require("damnit.message").report(err)
      end

      require("damnit.window").refresh()
    end,
  })
end

function M.stage()
  local picked = M.targets()

  if #picked.oids == 0 then
    return message.warn("nothing to stage on this line")
  end

  if picked.section == "staged" then
    return message.warn("already staged")
  end

  M.write(verb_args("add", picked.oids), "add")
end

function M.unstage()
  local picked = M.targets()

  if #picked.oids == 0 then
    return message.warn("nothing to stage on this line")
  end

  if picked.section ~= "staged" then
    return message.warn("not staged")
  end

  M.write(verb_args("reset", picked.oids), "reset")
end

--- Stage what is not staged, unstage what is.
function M.toggle_stage()
  local picked = M.targets()

  if #picked.oids == 0 then
    return message.warn("nothing to stage on this line")
  end

  local verb = picked.section == "staged" and "reset" or "add"
  M.write(verb_args(verb, picked.oids), verb)
end

--- `dam reset` with no oids unstages everything.
function M.unstage_all()
  local model = require("damnit.window").model()
  local staged = false

  for _, section in ipairs((model or {}).sections or {}) do
    staged = staged or section.kind == "staged"
  end

  if not staged then
    return message.warn("nothing is staged")
  end

  M.write({ "reset", "--json" }, "reset")
end
```

- [ ] **Step 4: Bind the keys**

In `lua/damnit/keys.lua`, add to the `damstatus` table, in both normal and visual mode where the spec
gives a range meaning:

```lua
    { { "n", "x" }, "-", act("toggle_stage"), "stage or unstage this object" },
    { { "n", "x" }, "s", act("stage"), "stage this object" },
    { { "n", "x" }, "u", act("unstage"), "unstage this object" },
    { "n", "U", act("unstage_all"), "unstage everything" },
```

`vim.keymap.set` takes a list of modes, so `M.attach` needs no change.

- [ ] **Step 5: Run it, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua keys_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: stage and unstage objects from the status window"
```

Expected: `6 passed, 0 failed`.

---

### Task 11: Discarding a working change, and the inline field diff

`X` ships for a `create` only, because `dam rm` is that op's exact inverse and dam has no verb that
restores a committed object. `=` draws the changed fields as virtual lines, so the buffer stays
unmodifiable and every other line keeps its number.

**Files:**

- Create: `lua/damnit/render/diff.lua`, `tests/diff_spec.lua`
- Modify: `lua/damnit/actions.lua`, `lua/damnit/keys.lua`, `lua/damnit/window.lua`

**Interfaces:**

- Produces:
  - `diff.set_fields(object) -> string[]`, every field the object has set, in dam's order.
  - `diff.value(object, field) -> string`, with `-` for unset.
  - `diff.virt_lines(entry) -> table[][]`, ready for `nvim_buf_set_extmark`'s `virt_lines`.
  - `actions.discard()`, `actions.toggle_diff()`.
  - `window.open_diffs(key) -> table<string, boolean>`, remembered by oid for the session and
    re-applied on every redraw.

- [ ] **Step 1: Write the failing test**

Create `tests/diff_spec.lua`:

```lua
-- The inline field diff, and what X will and will not throw away.

local diff = require("damnit.render.diff")
local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")

local BEFORE = { subject = "oat milk", labels = { "home" }, task = { priority = 1 } }
local AFTER = { subject = "buy oat milk", labels = { "errand", "home" }, task = { priority = 1, due = "2026-09-25" } }

return {
  ["shows an update as old on the left and new on the right"] = function()
    local lines = diff.virt_lines({
      op = "update",
      fields = { "subject", "labels", "due" },
      before = BEFORE,
      after = AFTER,
    })

    assert(#lines == 3, vim.inspect(lines))

    local text = table.concat(
      vim.tbl_map(function(chunk)
        return chunk[1]
      end, lines[1]),
      ""
    )
    assert(text:find("subject", 1, true), text)
    assert(text:find("oat milk", 1, true), text)
    assert(text:find("buy oat milk", 1, true), text)
    assert(text:find("->", 1, true), text)
  end,

  ["shows a create as every set field with no old column"] = function()
    local lines = diff.virt_lines({ op = "create", fields = {}, after = AFTER })
    local groups = {}

    for _, chunks in ipairs(lines) do
      for _, chunk in ipairs(chunks) do
        groups[#groups + 1] = chunk[2]
      end
    end

    assert(vim.tbl_contains(groups, "DamDiffNew"), vim.inspect(groups))
    assert(not vim.tbl_contains(groups, "DamDiffOld"), vim.inspect(groups))
  end,

  ["writes a dash for a field that is not set"] = function()
    assert(diff.value(BEFORE, "due") == "-", diff.value(BEFORE, "due"))
    assert(diff.value(AFTER, "due") == "2026-09-25", diff.value(AFTER, "due"))
    assert(diff.value(AFTER, "labels") == "errand, home", diff.value(AFTER, "labels"))
  end,

  ["X removes an uncommitted create after a confirm"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gs", "x", false)
      local before = #fake_dam.argv_log(fake)

      status_window.answer_input("y", function()
        vim.api.nvim_feedkeys("X", "x", false)
      end)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == "rm 660a08d0a1f74c9a3c2e5d8b7f1049ab6c3d2e51 --json",
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,

  ["X refuses an update, because dam has no verb that restores one"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("X", "x", false)

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(
        notifications[#notifications]
          == "damnit.nvim: dam has no verb that restores a committed object; commit the change or edit it back",
        notifications[#notifications]
      )
    end)
  end,
}
```

`status_window.answer_input(answer, run)` stubs `vim.ui.input` to call back with `answer`; add it to
`tests/helpers/status_window.lua` beside `with`.

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua diff_spec`
Expected: five FAILs, `module 'damnit.render.diff' not found`.

- [ ] **Step 3: Write the diff renderer**

Create `lua/damnit/render/diff.lua`:

```lua
-- The inline field diff, as extmark virtual lines.
--
-- Virtual lines rather than inserted text: the buffer stays unmodifiable, every
-- other entry keeps its line number so a remembered cursor survives, and a
-- change here is a set of field pairs rather than a hunk of text.

local M = {}

local status_model = require("damnit.status_model")

--- One field's value as text, with a dash for unset. A field lives either on the
--- object or inside its `task` or `event` table.
---@param object table?
---@param field string
---@return string
function M.value(object, field)
  if not object then
    return "-"
  end

  local value = object[field]

  if value == nil then
    value = (object.task or {})[field]
  end

  if value == nil then
    value = (object.event or {})[field]
  end

  if value == nil or value == vim.NIL or value == "" then
    return "-"
  end

  if type(value) == "table" then
    return #value > 0 and table.concat(value, ", ") or "-"
  end

  return tostring(value)
end

--- Every field one object has set, in dam's own order.
---@param object table?
---@return string[]
function M.set_fields(object)
  local names = {}

  for _, group in ipairs({ status_model.FIELDS, status_model.TASK_FIELDS, status_model.EVENT_FIELDS }) do
    for _, field in ipairs(group) do
      if M.value(object, field) ~= "-" then
        names[#names + 1] = field
      end
    end
  end

  return names
end

--- The virtual lines one change becomes.
---@param entry table
---@return table[][]
function M.virt_lines(entry)
  local fields = entry.fields or {}

  if entry.op == "create" then
    fields = M.set_fields(entry.after)
  elseif entry.op == "delete" then
    fields = M.set_fields(entry.before)
  end

  local lines = {}

  for _, field in ipairs(fields) do
    local chunks = { { ("           %-10s "):format(field), "DamFields" } }

    if entry.op == "create" then
      chunks[#chunks + 1] = { M.value(entry.after, field), "DamDiffNew" }
    elseif entry.op == "delete" then
      chunks[#chunks + 1] = { M.value(entry.before, field), "DamDiffOld" }
    else
      chunks[#chunks + 1] = { ("%-20s"):format(M.value(entry.before, field)), "DamDiffOld" }
      chunks[#chunks + 1] = { " ->  " }
      chunks[#chunks + 1] = { M.value(entry.after, field), "DamDiffNew" }
    end

    lines[#lines + 1] = chunks
  end

  return lines
end

return M
```

- [ ] **Step 4: Apply and remember the open diffs**

In `lua/damnit/window.lua`, add the per-store set and apply it at the end of `draw`:

```lua
---@type table<string, table<string, boolean>>
local diffs = {}

--- The oids whose inline diff is open, remembered for the session.
---@param key string?
---@return table<string, boolean>
function M.open_diffs(key)
  key = key or queue.key()
  diffs[key] = diffs[key] or {}

  return diffs[key]
end

---@param key string
local function apply_diffs(key)
  local buf = buffers[key]
  local open = M.open_diffs(key)
  local oids = vim.b[buf].damnit_oids or {}
  local kinds = vim.b[buf].damnit_kinds or {}
  local model = models[key]

  for index, oid in ipairs(oids) do
    if oid and open[oid] and kinds[index] == "change" then
      local found = nil

      for _, section in ipairs(model.sections) do
        for _, entry in ipairs(section.entries) do
          if entry.oid == oid and entry.kind == "change" then
            found = entry
          end
        end
      end

      if found then
        vim.api.nvim_buf_set_extmark(buf, render.NAMESPACE, index - 1, 0, {
          virt_lines = require("damnit.render.diff").virt_lines(found),
        })
      end
    end
  end
end
```

Call `apply_diffs(key)` from `draw`, right after `render.draw(buf, lines)`. An oid that is no longer
present simply draws nothing, which is how a diff is forgotten.

- [ ] **Step 5: Write the two actions**

Add to `lua/damnit/actions.lua`:

```lua
--- Throw away one working change.
---
--- Only a `create` has an exact inverse in dam: the object was never committed,
--- so removing it from the working layer leaves nothing behind. There is no
--- undo for it either, which is why the confirm has no way to be turned off.
function M.discard()
  local found = require("damnit.window").entry_under_cursor()

  if not found or found.entry.kind ~= "change" then
    return message.warn("nothing to discard on this line")
  end

  local entry = found.entry

  if entry.op ~= "create" then
    return message.warn("dam has no verb that restores a committed object; commit the change or edit it back")
  end

  vim.ui.input({
    prompt = ('Discard "%s"? This removes the object. (y/N) '):format(entry.subject),
  }, function(answer)
    if answer ~= "y" and answer ~= "Y" then
      return
    end

    M.write({ "rm", entry.oid, "--json" }, "rm")
  end)
end

--- Open or close the inline field diff of the change under the cursor.
function M.toggle_diff()
  local window = require("damnit.window")
  local found = window.entry_under_cursor()

  if not found or found.entry.kind ~= "change" then
    return message.warn("nothing to show on this line")
  end

  local open = window.open_diffs()
  open[found.entry.oid] = not open[found.entry.oid] or nil

  window.redraw_current()
end
```

`window.redraw_current()` redraws from the model already in hand, with no dam call:

```lua
--- Draw again from the model already in hand. No dam call, so a fold or a diff
--- toggle costs nothing.
---@param key string?
function M.redraw_current(key)
  key = key or queue.key()

  if not models[key] then
    return
  end

  draw(key, render.lines(models[key], { store = store_display(key), running = queue.running(key) }))
end
```

- [ ] **Step 6: Bind the keys, run, lint and commit**

In `lua/damnit/keys.lua`, in the `damstatus` table:

```lua
    { "n", "X", act("discard"), "discard this working change" },
    { "n", "=", act("toggle_diff"), "show or hide this change's fields" },
```

```bash
nvim --headless --clean -l tests/run.lua diff_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: discard an uncommitted create and show a change's fields inline"
```

Expected: `5 passed, 0 failed`.

---

### Task 12: Opening what the cursor is on

`<CR>` opens a change as a task buffer, a conflict as two read-only buffers side by side, and an
unpushed commit as a read-only list of its changes.

**Files:**

- Modify: `lua/damnit/actions.lua`, `lua/damnit/keys.lua`
- Create: `tests/open_spec.lua`

**Interfaces:**

- Consumes: `window.entry_under_cursor`, `window.origin`.
- Produces: `actions.open_under_cursor()`, `actions.open_conflict(entry)`,
  `actions.open_commit(id)`. Task 16 replaces the task-buffer call with the real one; until then
  `<CR>` on a change opens nothing and says so, which is a behaviour rather than a stub, and the case
  below pins it.

Ordering note: this task lands before the task buffer because the conflict and commit halves are
window work, and the task-buffer half is one line to change in Task 16.

- [ ] **Step 1: Write the failing test**

Create `tests/open_spec.lua`:

```lua
-- What <CR> opens, and what it leaves alone.

local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")

return {
  ["opens a conflict as ours and theirs, side by side and unmodifiable"] = function()
    status_window.with(function()
      vim.api.nvim_feedkeys("gc", "x", false)
      vim.api.nvim_feedkeys("\r", "x", false)

      local names = {}
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        names[#names + 1] = vim.api.nvim_buf_get_name(buf)
      end

      local ours, theirs = false, false
      for _, name in ipairs(names) do
        ours = ours or name:find("ours", 1, true) ~= nil
        theirs = theirs or name:find("theirs", 1, true) ~= nil
      end

      assert(ours and theirs, vim.inspect(names))

      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_get_name(buf):find("damnit://conflict", 1, true) then
          assert(vim.bo[buf].modifiable == false, "a conflict side is read only")
        end
      end
    end)
  end,

  ["opens an unpushed commit from dam show"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gp", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("\r", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1]:find("^show "), vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["does nothing on a heading or a notice"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gn", "x", false)
      local before = #fake_dam.argv_log(fake)
      local windows = #vim.api.nvim_list_wins()
      vim.api.nvim_feedkeys("\r", "x", false)

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(#vim.api.nvim_list_wins() == windows, "nothing was opened")
    end)
  end,
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua open_spec`
Expected: three FAILs, `attempt to call field 'open_under_cursor'`.

- [ ] **Step 3: Write the actions**

Add to `lua/damnit/actions.lua`:

```lua
--- One wire object in a read-only scratch buffer, in the current window.
---@param name string
---@param object table
---@return integer buf
local function read_only_object(name, object)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, require("damnit.task_format").render(object))
  vim.bo[buf].filetype = "damtask"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_buf(0, buf)

  return buf
end

--- Both sides of a conflict, ours on the left and theirs on the right. dam's
--- status carries the two objects in full, so this needs no call.
---@param entry table
function M.open_conflict(entry)
  local short = entry.oid:sub(1, 7)

  vim.cmd("vsplit")
  read_only_object(("damnit://conflict/%s/ours"):format(short), entry.ours or {})

  vim.cmd("vsplit")
  read_only_object(("damnit://conflict/%s/theirs"):format(short), entry.theirs or {})
end

--- One commit and the changes it carries, read only.
---@param id string
function M.open_commit(id)
  require("damnit.queue").submit({
    args = { "show", id, "--json" },
    label = "show",
    on_done = function(data, err)
      if err then
        return message.report(err)
      end

      local lines = { ("commit %s"):format(id:sub(1, 7)), "" }

      for _, change in ipairs((data or {}).changes or {}) do
        local object = change.after or change.before or {}
        lines[#lines + 1] = ("  %-8s %s  %s"):format(
          require("damnit.status_model").VERBS[change.op] or change.op,
          change.oid:sub(1, 7),
          tostring(object.subject or "")
        )
      end

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, ("damnit://commit/%s"):format(id:sub(1, 7)))
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].modifiable = false
      vim.api.nvim_win_set_buf(0, buf)
    end,
  })
end

--- Open whatever the cursor is on.
---
--- A change opens in the window `:Dam` was opened from, or in a split when the
--- status window is the only one.
function M.open_under_cursor()
  local window = require("damnit.window")
  local found = window.entry_under_cursor()

  if not found then
    return
  end

  local entry = found.entry

  if entry.kind == "conflict" then
    return M.open_conflict(entry)
  end

  if entry.kind == "remote" then
    return message.warn("this remote has no commit on this line")
  end

  if entry.kind ~= "change" then
    return
  end

  local origin = window.origin()

  if origin then
    vim.api.nvim_set_current_win(origin)
  else
    vim.cmd("split")
  end

  require("damnit.task_buffer").open(entry.oid)
end
```

Task 16 creates `damnit.task_buffer`. Until then `<CR>` on a change raises a module error, so this
task's third case avoids that line and Task 16's own spec covers it.

- [ ] **Step 4: Bind the key, run, lint and commit**

```lua
    { "n", "<CR>", act("open_under_cursor"), "open what the cursor is on" },
```

```bash
nvim --headless --clean -l tests/run.lua open_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: open a conflict and an unpushed commit from the status window"
```

Expected: `3 passed, 0 failed`.

---

### Task 13: The commit message buffer

`cc` opens a scratch buffer, `:w` commits. Write to commit rather than quit to commit, because
`dam commit -m` takes the message as an argument and there is no file for dam to read.

**Files:**

- Create: `lua/damnit/commit_buffer.lua`, `tests/commit_spec.lua`,
  `tests/fixtures/full/commit.json`
- Modify: `lua/damnit/actions.lua`, `lua/damnit/keys.lua`

**Interfaces:**

- Produces: `commit_buffer.open(key) -> integer?`, `commit_buffer.message(lines) -> string`,
  `commit_buffer.write(buf)`, `actions.commit()`.

- [ ] **Step 1: Write the fixture and the failing test**

`tests/fixtures/full/commit.json`:

```json
{"id": "7257572f1a0c4b3e9d8a6f2b5c1e7d0a3f4b6c8e", "at": "2026-09-20T10:00:00Z", "message": "stage", "changes": [{"oid": "660a08d0a1f74c9a3c2e5d8b7f1049ab6c3d2e51", "op": "create"}, {"oid": "78b8950b02735107aa608659dcf19f6f50adfeb1", "op": "update"}]}
```

Create `tests/commit_spec.lua`:

```lua
-- The commit message buffer: what it carries, what :w sends, and what it
-- refuses to send.

local commit_buffer = require("damnit.commit_buffer")
local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")

return {
  ["strips the comment lines and trims the rest"] = function()
    local message = commit_buffer.message({ "", "buy the milk", "", "# Staged", "# new 660a08d" })

    assert(message == "buy the milk", vim.inspect(message))
  end,

  ["finds no message in a buffer that is all comments and blanks"] = function()
    assert(commit_buffer.message({ "", "# Staged", "" }) == "", "an all-comment buffer commits nothing")
  end,

  ["cc opens a buffer carrying the staged changes as comments"] = function()
    status_window.with(function()
      vim.api.nvim_feedkeys("cc", "x", false)

      local buf = vim.api.nvim_get_current_buf()
      assert(vim.bo[buf].filetype == "damcommitmsg", vim.bo[buf].filetype)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert(lines[1] == "", "the cursor starts on an empty first line")

      local body = table.concat(lines, "\n")
      assert(body:find("# Staged", 1, true), body)
      assert(body:find("660a08d", 1, true), body)
    end)
  end,

  [":w sends dam commit -m and reports dam's own counts"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("cc", "x", false)
      vim.api.nvim_buf_set_lines(0, 0, 1, false, { "buy the milk" })

      local before = #fake_dam.argv_log(fake)
      vim.cmd("write")

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "commit -m buy the milk --json", vim.inspect(fake_dam.argv_log(fake)))
      assert(notifications[#notifications - 1] == "damnit.nvim: 7257572 committed, 2 changes", vim.inspect(notifications))
    end)
  end,

  ["refuses to commit an empty message and keeps the buffer open"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("cc", "x", false)
      local buf = vim.api.nvim_get_current_buf()
      local before = #fake_dam.argv_log(fake)

      vim.cmd("write")

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(vim.api.nvim_buf_is_valid(buf), "the buffer stays open to be fixed")
      assert(
        notifications[#notifications] == "damnit.nvim: no commit message; the commit was not made",
        notifications[#notifications]
      )
    end)
  end,
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua commit_spec`
Expected: five FAILs, `module 'damnit.commit_buffer' not found`.

- [ ] **Step 3: Write the module**

Create `lua/damnit/commit_buffer.lua`:

```lua
-- The commit message buffer and its write.
--
-- Written to commit rather than quit to commit: `dam commit -m` takes the
-- message as an argument, so this buffer is the plugin's own editing surface
-- rather than a file dam asked for.

local M = {}

local message = require("damnit.message")

--- The message a buffer's lines hold: everything that is not a comment line.
---@param lines string[]
---@return string
function M.message(lines)
  local kept = {}

  for _, line in ipairs(lines) do
    if not vim.startswith(line, "#") then
      kept[#kept + 1] = line
    end
  end

  return vim.trim(table.concat(kept, "\n"))
end

--- Send what the buffer holds, or say why nothing was sent.
---@param buf integer
function M.write(buf)
  local text = M.message(vim.api.nvim_buf_get_lines(buf, 0, -1, false))

  if text == "" then
    return message.warn("no commit message; the commit was not made")
  end

  require("damnit.queue").submit({
    args = { "commit", "-m", text, "--json" },
    label = "commit",
    on_done = function(report, err)
      if err then
        return message.report(err)
      end

      message.say(("%s committed, %d changes"):format(tostring(report.id):sub(1, 7), #(report.changes or {})))

      vim.bo[buf].modified = false
      vim.api.nvim_buf_delete(buf, { force = true })
      require("damnit.window").refresh()
    end,
  })
end

--- Open the message buffer for what is staged, or say nothing is.
---@param key string?
---@return integer? buf
function M.open(key)
  local model = require("damnit.window").model(key)
  local staged = nil

  for _, section in ipairs((model or {}).sections or {}) do
    if section.kind == "staged" then
      staged = section
    end
  end

  if not staged then
    message.warn("nothing is staged to commit")

    return nil
  end

  local lines = { "", "# Staged" }
  for _, entry in ipairs(staged.entries) do
    lines[#lines + 1] = ("# %-8s %s  %s"):format(entry.verb, entry.oid:sub(1, 7), entry.subject)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ("damnit://commit/%s"):format(key or require("damnit.queue").key()))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "damcommitmsg"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    desc = "dam: commit what this buffer says",
    callback = function()
      M.write(buf)
    end,
  })

  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("startinsert")

  return buf
end

return M
```

- [ ] **Step 4: Bind `cc`, run, lint and commit**

In `lua/damnit/actions.lua`:

```lua
function M.commit()
  require("damnit.commit_buffer").open()
end
```

In `lua/damnit/keys.lua`:

```lua
    { "n", "cc", act("commit"), "commit what is staged" },
```

```bash
nvim --headless --clean -l tests/run.lua commit_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: commit what is staged through a message buffer"
```

Expected: `5 passed, 0 failed`.

---

### Task 14: Push, pull and conflict resolution

The three network keys. Each is refused while another is running, each reports dam's own counts, and
each is followed by a fresh status.

**Files:**

- Modify: `lua/damnit/actions.lua`, `lua/damnit/keys.lua`
- Create: `tests/sync_spec.lua`, `tests/fixtures/full/pull.json`,
  `tests/fixtures/full/resolve.json`

**Interfaces:**

- Produces: `actions.push()`, `actions.pull()`, `actions.resolve(side)`,
  `actions.remote_under_cursor() -> string?`, `actions.sync(verb, remote)`.

- [ ] **Step 1: Write the fixtures and the failing test**

`tests/fixtures/full/pull.json`:

```json
{"remotes": [{"remote": "todoist", "created": 2, "updated": 1, "unchanged": 4, "conflicts": 0, "removed_upstream": 0}]}
```

`tests/fixtures/full/resolve.json`:

```json
{"oid": "7257572f1a0c4b3e9d8a6f2b5c1e7d0a3f4b6c8e", "resolved": "ours"}
```

Create `tests/sync_spec.lua`:

```lua
-- Push, pull and resolve: the argv each sends, and the sentence each reports.

local status_window = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/status_window.lua")
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")

return {
  ["P pushes every remote and reports dam's own counts"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("P", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before + 1
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "push --json", vim.inspect(fake_dam.argv_log(fake)))
      assert(fake_dam.argv_log(fake)[before + 2] == "status --json", "the window re-reads afterwards")

      local said = table.concat(notifications, "\n")
      assert(said:find("todoist: 3 sent, 3 ok, 0 failed, 0 skipped", 1, true), said)
    end)
  end,

  ["P on a remote's line pushes only that remote"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gp", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("P", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "push todoist --json", vim.inspect(fake_dam.argv_log(fake)))
    end)
  end,

  ["p pulls and reports what arrived"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("p", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(fake_dam.argv_log(fake)[before + 1] == "pull --json", vim.inspect(fake_dam.argv_log(fake)))

      local said = table.concat(notifications, "\n")
      assert(said:find("todoist: 2 new, 1 updated, 0 conflicts", 1, true), said)
    end)
  end,

  ["co and ct resolve the conflict under the cursor"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gc", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("co", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1]
          == "resolve 7257572f1a0c4b3e9d8a6f2b5c1e7d0a3f4b6c8e --ours --json",
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,

  ["co anywhere else sends nothing"] = function()
    status_window.with(function(fake, notifications)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("ct", "x", false)

      assert(#fake_dam.argv_log(fake) == before)
      assert(notifications[#notifications] == "damnit.nvim: no conflict on this line", notifications[#notifications])
    end)
  end,

  ["says there is nothing to push when no remote is behind"] = function()
    status_window.with(function(fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("P", "x", false)

      assert(#fake_dam.argv_log(fake) == before)
      assert(notifications[#notifications] == "damnit.nvim: nothing to push", notifications[#notifications])
    end, (arg[0]:match("(.*)/") or ".") .. "/fixtures/default")
  end,
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua sync_spec`
Expected: six FAILs, `attempt to call field 'push'`.

- [ ] **Step 3: Write the actions**

Add to `lua/damnit/actions.lua`:

```lua
--- The remote the cursor is on, when it is on one.
---@return string?
function M.remote_under_cursor()
  local found = require("damnit.window").entry_under_cursor()

  if found and found.entry.kind == "remote" then
    return found.entry.remote
  end

  return nil
end

---@param report table
---@return string[]
local function push_lines(report)
  local said = {}

  for _, each in ipairs((report or {}).remotes or {}) do
    said[#said + 1] = ("%s: %d sent, %d ok, %d failed, %d skipped"):format(
      each.remote,
      each.sent or 0,
      each.succeeded or 0,
      #(each.failed or {}),
      each.skipped or 0
    )
  end

  return said
end

---@param report table
---@return string[]
local function pull_lines(report)
  local said = {}

  for _, each in ipairs((report or {}).remotes or {}) do
    said[#said + 1] = ("%s: %d new, %d updated, %d conflicts"):format(
      each.remote,
      each.created or 0,
      each.updated or 0,
      each.conflicts or 0
    )
  end

  return said
end

--- One network call, refused while another is in flight.
---@param verb "push"|"pull"
---@param remote string?
function M.sync(verb, remote)
  local args = { verb }

  if remote then
    args[#args + 1] = remote
  end

  args[#args + 1] = "--json"

  local label = remote and ("%s %s"):format(verb, remote) or verb

  require("damnit.queue").submit({
    args = args,
    label = label,
    verb = verb,
    network = true,
    on_done = function(report, err)
      if err then
        message.report(err)

        -- A credential command cannot prompt from here: vim.system closes
        -- standard input, so an interactive vault CLI never sees a terminal.
        -- dam names all three credential failures with the one kind, and the
        -- rule is null for each, so the advice covers the command and the
        -- source together.
        if err.kind == "credential" then
          message.warn(
            "dam could not resolve this remote's credential; if its source is a command that prompts, run dam "
              .. verb
              .. " in a terminal, and otherwise fix the source in dam's config"
          )
        end
      else
        for _, line in ipairs(verb == "push" and push_lines(report) or pull_lines(report)) do
          message.say(line)
        end
      end

      require("damnit.window").forget_remotes()
      require("damnit.window").refresh()
    end,
  })
end

function M.push()
  local model = require("damnit.window").model()
  local behind = false

  for _, remote in ipairs((model or {}).remotes or {}) do
    behind = behind or remote.commits > 0
  end

  if not behind then
    return message.warn("nothing to push")
  end

  M.sync("push", M.remote_under_cursor())
end

function M.pull()
  M.sync("pull", M.remote_under_cursor())
end

--- Resolve the conflict under the cursor with one side or the other.
---@param side "ours"|"theirs"
function M.resolve(side)
  local found = require("damnit.window").entry_under_cursor()

  if not found or found.entry.kind ~= "conflict" then
    return message.warn("no conflict on this line")
  end

  M.write({ "resolve", found.entry.oid, "--" .. side, "--json" }, "resolve")
end
```

- [ ] **Step 4: Bind the keys, run, lint and commit**

In `lua/damnit/keys.lua`:

```lua
    { "n", "P", act("push"), "push" },
    { "n", "p", act("pull"), "pull" },
    {
      "n",
      "co",
      function()
        require("damnit.actions").resolve("ours")
      end,
      "resolve this conflict with ours",
    },
    {
      "n",
      "ct",
      function()
        require("damnit.actions").resolve("theirs")
      end,
      "resolve this conflict with theirs",
    },
```

```bash
nvim --headless --clean -l tests/run.lua sync_spec
nvim --headless --clean -l tests/run.lua | tail -1
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: push, pull and resolve conflicts from the status window"
```

Expected: `6 passed, 0 failed`, then the whole suite green.

---

### Task 15: The task frontmatter, retargeted at dam's fields

The header keeps `todoist.nvim`'s shape and changes its field set. `path` becomes editable, `priority`
reverses, and `depends`, `deadline` and `recurrence` arrive. Pure: no buffer, no call.

**Files:**

- Rewrite: `lua/damnit/task_format.lua`, `tests/task_format_spec.lua`

Start from the file as it stands (`git show HEAD:lua/damnit/task_format.lua`), which already has the
fence parsing and the label splitting.

**Interfaces:**

- Produces:
  - `task_format.render(object) -> string[]`
  - `task_format.parse(lines) -> table?, string?, string?` where the table maps a key to
    `{ value: string, line: integer }`
  - `task_format.changes(object, header, body) -> { edit: string[], move: string? }?, { message: string, line: integer }?`
  - `task_format.TASK_KEYS`, `task_format.EVENT_KEYS`, `task_format.FENCE`

- [ ] **Step 1: Write the failing test**

Rewrite `tests/task_format_spec.lua`:

```lua
-- The frontmatter, both directions, and the flags one edit becomes.

local task_format = require("damnit.task_format")

local TASK = {
  oid = "78b8950b02735107aa608659dcf19f6f50adfeb1",
  kind = "task",
  subject = "buy oat milk",
  body = "The kind in the grey carton.",
  path = "inbox/",
  labels = { "errand", "home" },
  depends = {},
  reminders = {},
  task = { done = false, priority = 1, due = "2026-09-25" },
}

---@param object table
---@param edits table<string, string>
---@return { edit: string[], move: string? }?
---@return table? refusal
local function after(object, edits)
  local lines = task_format.render(object)

  for index, line in ipairs(lines) do
    local key = line:match("^(%l[%l_]*):")
    if key and edits[key] then
      lines[index] = ("%s: %s"):format(key, edits[key])
    end
  end

  local header, body = task_format.parse(lines)

  return task_format.changes(object, header, body)
end

return {
  ["renders the header dam's way, priority first and reversed"] = function()
    local lines = task_format.render(TASK)

    assert(lines[1] == "---", lines[1])
    assert(vim.tbl_contains(lines, "subject: buy oat milk"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "path: inbox/"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "priority: 1"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "labels: errand, home"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "depends:"), "an empty field is `key:` with no trailing space")
    assert(vim.tbl_contains(lines, "# priority: 1 is highest"), vim.inspect(lines))
    assert(lines[#lines] == "The kind in the grey carton.", lines[#lines])
  end,

  ["sends only what changed"] = function()
    local changes = after(TASK, { subject = "buy the oat milk" })

    assert(vim.deep_equal(changes.edit, { "--subject", "buy the oat milk" }), vim.inspect(changes.edit))
  end,

  ["clears a due date with --no-due rather than an empty --due"] = function()
    local changes = after(TASK, { due = "" })

    assert(vim.deep_equal(changes.edit, { "--no-due" }), vim.inspect(changes.edit))
  end,

  ["diffs labels and depends as sets"] = function()
    local changes = after(TASK, { labels = "home, slow" })

    assert(vim.deep_equal(changes.edit, { "--label", "slow", "--unlabel", "errand" }), vim.inspect(changes.edit))
  end,

  ["makes a changed path a move rather than an edit"] = function()
    local changes = after(TASK, { path = "home/errands/" })

    assert(changes.move == "home/errands/", tostring(changes.move))
    assert(#changes.edit == 0, vim.inspect(changes.edit))
  end,

  ["refuses an empty subject and a priority outside dam's range, on the right line"] = function()
    local _, refused = after(TASK, { subject = "" })
    assert(refused.message:find("subject", 1, true), refused.message)
    assert(refused.line > 1, tostring(refused.line))

    local _, bad = after(TASK, { priority = "9" })
    assert(bad.message:find("1, 2, 3 or 4", 1, true), bad.message)
    assert(bad.message:find("1 is the most urgent", 1, true), bad.message)
  end,

  ["refuses a depends entry too short to be an oid prefix"] = function()
    local _, refused = after(TASK, { depends = "abc" })

    assert(refused.message:find("four", 1, true), refused.message)
  end,

  ["reads an event's own fields"] = function()
    local event = {
      oid = "660a08d0a1f74c9a3c2e5d8b7f1049ab6c3d2e51",
      kind = "event",
      subject = "standup",
      body = "",
      path = "work/",
      labels = {},
      depends = {},
      reminders = {},
      event = { start = "2026-09-21T09:00:00", ["end"] = "2026-09-21T09:15:00", timezone = "UTC" },
    }
    local lines = task_format.render(event)

    assert(vim.tbl_contains(lines, "start: 2026-09-21T09:00:00"), vim.inspect(lines))
    assert(vim.tbl_contains(lines, "timezone: UTC"), vim.inspect(lines))
    assert(not vim.tbl_contains(lines, "priority: 1"), "an event has no priority")
  end,
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua task_format_spec`
Expected: eight FAILs on the old field set.

- [ ] **Step 3: Rewrite the module**

Replace `lua/damnit/task_format.lua`. The fence handling and the label splitting come across
unchanged; the field set, the comment lines and the flag map are new.

```lua
-- The text one object looks like in a buffer, and the reading of it back.
--
-- A header of `key: value` lines between two `---` fences and the body as
-- markdown below them. Comment lines inside the header start with `#` and are
-- read-only: they carry what dam has no edit flag for.
--
-- Pure: no buffer, no call, no notification.

local M = {}

M.FENCE = "---"

M.TASK_KEYS = { "subject", "path", "priority", "due", "deadline", "labels", "depends", "recurrence" }
M.EVENT_KEYS = { "subject", "path", "start", "end", "timezone", "location", "labels", "depends" }

--- The flag that sets a field, and the flag that clears it. `false` means the
--- field cannot be cleared, so an empty value is refused.
local FLAGS = {
  subject = { "--subject", false },
  body = { "--body", "" },
  priority = { "-p", false },
  due = { "--due", "--no-due" },
  deadline = { "--deadline", "--no-deadline" },
  recurrence = { "--recurrence", "--no-recurrence" },
  start = { "--start", false },
  ["end"] = { "--end", false },
  timezone = { "--timezone", false },
  location = { "--location", "--no-location" },
}

---@param value any
---@return string
local function text(value)
  if value == nil or value == vim.NIL then
    return ""
  end

  return tostring(value)
end

---@param object table
---@param field string
---@return string
local function field_value(object, field)
  local group = object.kind == "event" and object.event or object.task

  if field == "labels" or field == "depends" then
    return table.concat(object[field] or {}, ", ")
  end

  if object[field] ~= nil then
    return text(object[field])
  end

  return text((group or {})[field])
end

---@param key string
---@param value string
---@return string
local function line_of(key, value)
  if value == "" then
    return key .. ":"
  end

  return ("%s: %s"):format(key, value)
end

--- The keys one object's kind uses.
---@param object table
---@return string[]
function M.keys(object)
  return object.kind == "event" and M.EVENT_KEYS or M.TASK_KEYS
end

--- The lines one object becomes.
---@param object table
---@return string[]
function M.render(object)
  local lines = { M.FENCE }

  for _, key in ipairs(M.keys(object)) do
    lines[#lines + 1] = line_of(key, field_value(object, key))
  end

  -- Read only: dam has no edit flag for reminders, and dam's priority scale is
  -- the reverse of Todoist's.
  lines[#lines + 1] = "# reminders: " .. (table.concat(object.reminders or {}, ", "))

  if object.kind ~= "event" then
    lines[#lines + 1] = "# priority: 1 is highest"
  end

  lines[#lines + 1] = M.FENCE
  vim.list_extend(lines, vim.split(text(object.body), "\n", { plain = true }))

  return lines
end

--- Read a buffer back into a header and a body.
---@param lines string[]
---@return table? header key to { value, line }
---@return string? body
---@return string? err
function M.parse(lines)
  if lines[1] ~= M.FENCE then
    return nil, nil, ("the first line must be %s, the header fence"):format(M.FENCE)
  end

  local header, closed = {}, nil

  for index = 2, #lines do
    local line = lines[index]

    if line == M.FENCE then
      closed = index
      break
    end

    if not vim.startswith(line, "#") then
      local key, value = line:match("^(%l[%l_]*):%s*(.-)%s*$")

      if not key then
        return nil, nil, ("line %d is not a `key: value` header line: %s"):format(index, line)
      end

      if header[key] then
        return nil, nil, ("line %d repeats the field `%s`"):format(index, key)
      end

      header[key] = { value = value, line = index }
    end
  end

  if not closed then
    return nil, nil, ("the header has no closing %s fence"):format(M.FENCE)
  end

  return header, table.concat(vim.list_slice(lines, closed + 1), "\n")
end

---@param value string
---@return string[]
local function split(value)
  local items = {}

  for item in value:gmatch("[^,]+") do
    local trimmed = vim.trim(item)

    if trimmed ~= "" then
      items[#items + 1] = trimmed
    end
  end

  return items
end

---@param wanted string[]
---@param held string[]
---@return string[] added
---@return string[] removed
local function set_diff(wanted, held)
  local have, want = {}, {}

  for _, item in ipairs(held) do
    have[item] = true
  end
  for _, item in ipairs(wanted) do
    want[item] = true
  end

  local added, removed = {}, {}

  for _, item in ipairs(wanted) do
    if not have[item] then
      added[#added + 1] = item
    end
  end
  for _, item in ipairs(held) do
    if not want[item] then
      removed[#removed + 1] = item
    end
  end

  return added, removed
end

--- What a write should send, given the object dam last described and the buffer
--- as the operator left it.
---
--- Only what changed is sent, which matters most for `due`: dam parses a due
--- string, and a round trip through an unchanged one could move a recurrence.
---@param object table
---@param header table
---@param body string
---@return { edit: string[], move: string? }?
---@return { message: string, line: integer }?
function M.changes(object, header, body)
  local allowed = M.keys(object)
  local edit, move = {}, nil

  for key, entry in pairs(header) do
    if not vim.tbl_contains(allowed, key) then
      return nil, { message = ("`%s` is not a field of a %s"):format(key, object.kind or "task"), line = entry.line }
    end
  end

  local subject = header.subject
  if subject and subject.value == "" then
    return nil, { message = "`subject` is empty, and an object has to say something", line = subject.line }
  end

  local priority = header.priority
  if priority then
    local number = tonumber(priority.value)

    if not number or number % 1 ~= 0 or number < 1 or number > 4 then
      return nil, {
        message = ("`priority` is %s: it has to be 1, 2, 3 or 4, where 1 is the most urgent"):format(priority.value),
        line = priority.line,
      }
    end
  end

  local depends = header.depends
  if depends then
    for _, oid in ipairs(split(depends.value)) do
      if not oid:match("^%x%x%x%x%x*$") then
        return nil, {
          message = ("`%s` is not an oid: at least four hex characters"):format(oid),
          line = depends.line,
        }
      end
    end
  end

  local path = header.path
  if path and path.value ~= field_value(object, "path") then
    for segment in path.value:gmatch("[^/]*") do
      if segment == "" and not vim.endswith(path.value, "/") then
        return nil, { message = "`path` has an empty segment", line = path.line }
      end
    end

    move = path.value
  end

  for _, key in ipairs(allowed) do
    local entry = header[key]

    if entry and key ~= "path" then
      local held = field_value(object, key)

      if entry.value ~= held then
        if key == "labels" or key == "depends" then
          local added, removed = set_diff(split(entry.value), object[key] or {})
          local set = key == "labels" and "--label" or "--depends"
          local clear = key == "labels" and "--unlabel" or "--undepends"

          for _, item in ipairs(added) do
            vim.list_extend(edit, { set, item })
          end
          for _, item in ipairs(removed) do
            vim.list_extend(edit, { clear, item })
          end
        elseif entry.value == "" then
          local clear = FLAGS[key][2]

          if not clear then
            return nil, { message = ("`%s` cannot be cleared"):format(key), line = entry.line }
          end

          edit[#edit + 1] = clear
        else
          vim.list_extend(edit, { FLAGS[key][1], entry.value })
        end
      end
    end
  end

  if body ~= text(object.body) then
    vim.list_extend(edit, { "--body", body })
  end

  return { edit = edit, move = move }
end

return M
```

- [ ] **Step 4: Run it, prove it is pure, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua task_format_spec
grep -nE 'vim\.(api|fn|system|notify|schedule)' lua/damnit/task_format.lua
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "refactor: retarget the task frontmatter at dam's field set"
```

Expected: `8 passed, 0 failed`, and the grep finds nothing.

---

### Task 16: The task buffer

`:Dam task <oid>` and `<CR>` on a change. One object as a buffer, written back as one `dam edit` plus a
`dam mv` when the path changed, with both kinds of refusal shown as diagnostics on the line at fault.

**Files:**

- Create: `lua/damnit/task_buffer.lua`, `tests/task_buffer_spec.lua`
- Modify: `plugin/damnit.lua`, `lua/damnit/init.lua`
- Create: `tests/fixtures/full/show.json`, `tests/fixtures/full/edit.json`, `tests/fixtures/full/mv.json`

**Interfaces:**

- Produces: `task_buffer.open(oid) -> integer buf`, `task_buffer.show(object) -> integer buf`,
  `task_buffer.write(buf)`, `task_buffer.NAMESPACE`.

- [ ] **Step 1: Write the three fixtures**

Each is one wire object. `show.json` and `edit.json` hold the object from `full/status.json`'s
`unstaged[1].after`; `mv.json` holds the same object with `"path": "home/errands/"`.

- [ ] **Step 2: Write the failing test**

Create `tests/task_buffer_spec.lua` with these cases:

```lua
-- One object as a buffer: what it draws, what :w sends, and where a refusal
-- lands.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local task_buffer = require("damnit.task_buffer")
local queue = require("damnit.queue")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

---@param run fun(buf: integer, fake: damnit.FakeDam, notifications: string[])
---@param opts table?
local function with_task(run, opts)
  local fake = fake_dam.install(vim.tbl_extend("force", { fixtures = TESTS_DIR .. "/fixtures/full" }, opts or {}))
  queue.reset()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local buf = task_buffer.open("78b8950b02735107aa608659dcf19f6f50adfeb1")
  fake_dam.settle(function()
    return vim.api.nvim_buf_line_count(buf) > 1
  end)

  local ok, err = pcall(run, buf, fake, notifications)

  vim.notify = real
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

---@param buf integer
---@param key string
---@param value string
local function set_field(buf, key, value)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^" .. key .. ":") then
      vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { ("%s: %s"):format(key, value) })

      return
    end
  end

  error("no " .. key .. " line in the buffer")
end

return {
  ["reads the object with dam show and draws its frontmatter"] = function()
    with_task(function(buf, fake)
      assert(
        vim.tbl_contains(fake_dam.argv_log(fake), "show 78b8950b02735107aa608659dcf19f6f50adfeb1 --json"),
        vim.inspect(fake_dam.argv_log(fake))
      )
      assert(vim.bo[buf].filetype == "damtask", vim.bo[buf].filetype)
      assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "---")
    end)
  end,

  ["sends only the changed field and marks the buffer unmodified"] = function()
    with_task(function(buf, fake)
      set_field(buf, "subject", "buy the oat milk")
      local before = #fake_dam.argv_log(fake)
      vim.cmd("write")

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1]
          == "edit 78b8950b02735107aa608659dcf19f6f50adfeb1 --subject buy the oat milk --json",
        vim.inspect(fake_dam.argv_log(fake))
      )
      assert(vim.bo[buf].modified == false, "a landed write leaves the buffer unmodified")
    end)
  end,

  ["sends a changed path as a second call to dam mv"] = function()
    with_task(function(buf, fake)
      set_field(buf, "path", "home/errands/")
      local before = #fake_dam.argv_log(fake)
      vim.cmd("write")

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == "mv 78b8950b02735107aa608659dcf19f6f50adfeb1 home/errands/ --json",
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,

  ["sends nothing when nothing changed"] = function()
    with_task(function(buf, fake, notifications)
      local before = #fake_dam.argv_log(fake)
      vim.cmd("write")

      assert(#fake_dam.argv_log(fake) == before, "nothing was sent")
      assert(notifications[#notifications] == "damnit.nvim: nothing changed", notifications[#notifications])
      assert(vim.bo[buf].modified == false)
    end)
  end,

  ["puts a local refusal on the line it is about, and sends nothing"] = function()
    with_task(function(buf, fake)
      set_field(buf, "priority", "9")
      local before = #fake_dam.argv_log(fake)
      vim.cmd("write")

      assert(#fake_dam.argv_log(fake) == before, "a local refusal costs no call")

      local found = vim.diagnostic.get(buf, { namespace = task_buffer.NAMESPACE })
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message:find("1, 2, 3 or 4", 1, true), found[1].message)
      assert(vim.bo[buf].modified == true, "the text stays where it can be fixed")
    end)
  end,

  ["puts dam's own refusal on line one and leaves the buffer modified"] = function()
    with_task(function(buf, fake)
      set_field(buf, "depends", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77")
      local before = #fake_dam.argv_log(fake)
      vim.cmd("write")

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)
      fake_dam.settle(function()
        return #vim.diagnostic.get(buf, { namespace = task_buffer.NAMESPACE }) > 0
      end)

      local found = vim.diagnostic.get(buf, { namespace = task_buffer.NAMESPACE })
      assert(found[1].message:find("would make a cycle", 1, true), found[1].message)
      assert(vim.bo[buf].modified == true)
    end)
  end,
}
```

The last case installs the fake with `exit = 4` and an error document whose `rule` is `cycle` and
whose `message` is `78b8950 depends on a9db854, which would make a cycle`.

- [ ] **Step 3: Run it and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua task_buffer_spec`
Expected: six FAILs, `module 'damnit.task_buffer' not found`.

- [ ] **Step 4: Write the module**

Create `lua/damnit/task_buffer.lua`:

```lua
-- One object as a buffer.
--
-- The buffer stays modified until dam answers, so an edit that has not landed
-- still reads as unwritten and a refused one leaves the text where it can be
-- fixed.

local M = {}

local message = require("damnit.message")
local task_format = require("damnit.task_format")

M.NAMESPACE = vim.api.nvim_create_namespace("damnit")

---@type table<integer, table>
local objects = {}

---@param buf integer
---@param text string
---@param line integer
local function diagnose(buf, text, line)
  vim.diagnostic.set(buf, M.NAMESPACE, {
    {
      lnum = math.max(line - 1, 0),
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      source = "damnit",
      message = text,
    },
  })
end

--- Draw one object and remember it, so the next write knows what changed.
---@param object table
---@param buf integer?
---@return integer buf
function M.show(object, buf)
  buf = buf or vim.api.nvim_get_current_buf()

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, task_format.render(object))
  vim.bo[buf].modified = false

  objects[buf] = object
  vim.diagnostic.reset(M.NAMESPACE, buf)

  return buf
end

--- Send what the buffer changed: one `dam edit`, and `dam mv` when the path did.
---@param buf integer
function M.write(buf)
  local object = objects[buf]
  if not object then
    return message.warn("this buffer has no object to write")
  end

  vim.diagnostic.reset(M.NAMESPACE, buf)

  local header, body, err = task_format.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if err then
    return diagnose(buf, err, 1)
  end

  local changes, refused = task_format.changes(object, header, body)
  if refused then
    return diagnose(buf, refused.message, refused.line)
  end

  if #changes.edit == 0 and not changes.move then
    vim.bo[buf].modified = false

    return message.warn("nothing changed")
  end

  local queue = require("damnit.queue")

  if #changes.edit > 0 then
    local args = { "edit", object.oid }
    vim.list_extend(args, changes.edit)
    args[#args + 1] = "--json"

    queue.submit({
      args = args,
      label = "edit",
      on_done = function(updated, failure)
        if failure then
          return diagnose(buf, failure.message, 1)
        end

        M.show(updated, buf)
      end,
    })
  end

  if changes.move then
    queue.submit({
      args = { "mv", object.oid, changes.move, "--json" },
      label = "mv",
      on_done = function(updated, failure)
        if failure then
          return diagnose(buf, failure.message, 1)
        end

        M.show(updated, buf)
      end,
    })
  end
end

--- Open one object by oid.
---@param oid string
---@return integer buf
function M.open(oid)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(buf, ("damnit://task/%s"):format(oid))
  vim.bo[buf].filetype = "damtask"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.api.nvim_win_set_buf(0, buf)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    desc = "dam: write this object back",
    callback = function()
      M.write(buf)
    end,
  })

  require("damnit.queue").submit({
    args = { "show", oid, "--json" },
    label = "show",
    on_done = function(object, err)
      if err then
        return message.report(err)
      end

      M.show(object, buf)
    end,
  })

  return buf
end

return M
```

- [ ] **Step 5: Wire the command and the keymap function**

In `plugin/damnit.lua`, add to `SUBCOMMANDS`:

```lua
  task = function(args)
    if #args ~= 1 then
      return vim.notify("damnit.nvim: usage is :Dam task <oid>", vim.log.levels.ERROR)
    end

    require("damnit.task_buffer").open(args[1])
  end,
```

- [ ] **Step 6: Run it, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua task_buffer_spec
nvim --headless --clean -l tests/run.lua open_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: edit one dam object as a buffer"
```

Expected: `6 passed, 0 failed`, and `open_spec` still green.

---

### Task 17: The tree and the list's lines, on `path`

`dam` models the tree as `path`, so the tree is string work rather than a `parent_id` lookup. Both
modules stay pure.

**A note on `path` that the implementer must confirm before writing the code.** The spec says an
object's children are the objects nested under its path, and that `>` sends
`dam mv <oid> <parent path>/<own segment>`. Both readings of `path` (a container the object sits in, or
a path that ends in the object's own segment) agree on one rule, which is what this task implements: an
object's parent is the object whose path is this object's path with its last segment removed. Confirm
it once against the real binary before Step 3:

```bash
dam new "parent" --path work/ --json
dam new "child" --path work/parent/ --json
dam ls --json | jq '.[] | {oid, subject, path}'
```

If the child's path is not the parent's path plus one segment, stop and re-read
`crates/dam-domain` before going on.

**Files:**

- Rewrite: `lua/damnit/tree.lua`, `tests/tree_spec.lua`
- Rewrite: `lua/damnit/list_format.lua`, `tests/list_format_spec.lua`

**Interfaces:**

- Produces:
  - `tree.parent_path(path) -> string`, `tree.own_segment(path) -> string`
  - `tree.index(objects) -> { by_path, children }`
  - `tree.is_root(tree, object) -> boolean`, `tree.child_count`, `tree.descendant_count`,
    `tree.descend(tree, object, collapsed, visit, depth)`
  - `tree.indent_to(object, above) -> string?, string?` and `tree.promote_to(object, tree) -> string?, string?`,
    each answering with the path `dam mv` should be given, or nil and a reason
  - `list_format.render(spec, objects, collapsed) -> string[], table[]`, the lines and one entry per line
  - `list_format.object_line(object, indent, folded) -> string`, `list_format.title(spec)`

- [ ] **Step 1: Write the failing tests**

Rewrite `tests/tree_spec.lua` around the path rule:

```lua
local tree = require("damnit.tree")

local PARENT = { oid = "aaaa1111", subject = "parent", path = "work/parent/" }
local CHILD = { oid = "bbbb2222", subject = "child", path = "work/parent/child/" }
local OTHER = { oid = "cccc3333", subject = "other", path = "work/other/" }

return {
  ["reads a parent path by dropping the last segment"] = function()
    assert(tree.parent_path("work/parent/child/") == "work/parent/", tree.parent_path("work/parent/child/"))
    assert(tree.parent_path("work/") == "", tree.parent_path("work/"))
    assert(tree.parent_path("") == "", tree.parent_path(""))
    assert(tree.own_segment("work/parent/child/") == "child", tree.own_segment("work/parent/child/"))
  end,

  ["indexes children under the object whose path they extend"] = function()
    local index = tree.index({ PARENT, CHILD, OTHER })

    assert(tree.child_count(index, "work/parent/") == 1)
    assert(tree.descendant_count(index, "work/") == 0, "work/ is not an object in this view")
    assert(tree.is_root(index, PARENT), "its parent is not in the view, so it heads the tree")
    assert(not tree.is_root(index, CHILD))
  end,

  ["indents under the row above and carries the subtree with it"] = function()
    local destination, refusal = tree.indent_to(CHILD, OTHER)

    assert(destination == "work/other/child/", tostring(destination) .. " " .. tostring(refusal))
  end,

  ["refuses to indent what is already there, and to promote a root"] = function()
    local _, already = tree.indent_to(CHILD, PARENT)
    assert(already:find("already under", 1, true), already)

    local _, top = tree.promote_to(PARENT, tree.index({ PARENT }))
    assert(top:find("top level", 1, true), top)
  end,

  ["promotes to the grandparent's path"] = function()
    local destination = tree.promote_to(CHILD, tree.index({ PARENT, CHILD }))

    assert(destination == "work/child/", tostring(destination))
  end,
}
```

Rewrite `tests/list_format_spec.lua` around dam's own fields: the subject, the due date, the priority
badge (1 is most urgent), the labels, the path, and the fold marker with a descendant count. Keep the
existing cases' shape and change what they read, which is the smallest honest port.

- [ ] **Step 2: Run them and watch them fail**

Run: `nvim --headless --clean -l tests/run.lua tree_spec`
Expected: five FAILs on the old `parent_id` functions.

- [ ] **Step 3: Rewrite `tree.lua`**

```lua
-- Subtasks as a tree, which in dam is a tree of paths.
--
-- An object's parent is the object whose path is this one's path with the last
-- segment removed. A view that holds a child and not its parent draws the child
-- at the top level, because a query can match one without the other.

local M = {}

---@param path any
---@return string
local function text(path)
  if path == nil or path == vim.NIL then
    return ""
  end

  return tostring(path)
end

--- The path one level up. `work/parent/child/` becomes `work/parent/`.
---@param path string
---@return string
function M.parent_path(path)
  local trimmed = text(path):gsub("/$", "")
  local parent = trimmed:match("^(.*)/[^/]*$")

  return parent and (parent .. "/") or ""
end

--- The object's own last segment.
---@param path string
---@return string
function M.own_segment(path)
  return (text(path):gsub("/$", ""):match("([^/]*)$")) or ""
end

---@class damnit.Tree
---@field by_path table<string, table>
---@field children table<string, table[]>

--- Index one view's objects by path and by parent.
---@param objects table[]
---@return damnit.Tree
function M.index(objects)
  local index = { by_path = {}, children = {} }

  for _, object in ipairs(objects or {}) do
    index.by_path[text(object.path)] = object
  end

  for _, object in ipairs(objects or {}) do
    local parent = M.parent_path(text(object.path))

    if index.by_path[parent] then
      index.children[parent] = index.children[parent] or {}
      table.insert(index.children[parent], object)
    end
  end

  return index
end

---@param index damnit.Tree
---@param object table
---@return boolean
function M.is_root(index, object)
  return index.by_path[M.parent_path(text(object.path))] == nil
end

---@param index damnit.Tree
---@param path string
---@return integer
function M.child_count(index, path)
  return #(index.children[path] or {})
end

--- How many objects sit under this one at every depth, which is what a folded
--- line's badge counts.
---@param index damnit.Tree
---@param path string
---@return integer
function M.descendant_count(index, path)
  local count = 0

  for _, child in ipairs(index.children[path] or {}) do
    count = count + 1 + M.descendant_count(index, text(child.path))
  end

  return count
end

--- Walk an object and its descendants, calling `visit` with each and its depth.
--- A collapsed object is visited and its descendants are not, so a fold means
--- lines that were never drawn.
---@param index damnit.Tree
---@param object table
---@param collapsed table<string, boolean>
---@param visit fun(object: table, depth: integer)
---@param depth integer?
function M.descend(index, object, collapsed, visit, depth)
  local level = depth or 0
  visit(object, level)

  local path = text(object.path)
  if collapsed[path] then
    return
  end

  for _, child in ipairs(index.children[path] or {}) do
    M.descend(index, child, collapsed, visit, level + 1)
  end
end

--- Where `>` sends the object on the cursor: under the object on the row above.
--- dam carries the subtree along, so only the object's own path is given.
---@param object table
---@param above table?
---@return string? destination
---@return string? refusal
function M.indent_to(object, above)
  if not above then
    return nil, "nothing above this object to indent it under"
  end

  local path = text(object.path)
  if M.parent_path(path) == text(above.path) then
    return nil, "already under " .. tostring(above.subject)
  end

  return text(above.path) .. M.own_segment(path) .. "/"
end

--- Where `<` sends it: out from under its parent, one level up.
---@param object table
---@param index damnit.Tree
---@return string? destination
---@return string? refusal
function M.promote_to(object, index)
  local path = text(object.path)
  local parent = M.parent_path(path)

  if parent == "" or index.by_path[parent] == nil then
    return nil, "already at the top level"
  end

  return M.parent_path(parent) .. M.own_segment(path) .. "/"
end

return M
```

- [ ] **Step 4: Rewrite `list_format.lua`**

Start from `git show HEAD:lua/damnit/list_format.lua`. Three changes, and nothing else:

1. `labels_of`, `due_of` and `append_badges` read `object.labels`, `object.task.due` and
   `object.task.priority`, and the priority badge reverses: `p1` is the most urgent and takes
   `DamPriority1`.
1. The grouping by project and section goes. dam has one `path`, so the tree is the layout and the
   path is shown at the end of each line.
1. `render` walks `tree.index` and `tree.descend` rather than the project and section maps, and hands
   back a parallel list of the object drawn on each line, which is what the list buffer reads at the
   cursor.

- [ ] **Step 5: Run, prove both are pure, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua tree_spec
nvim --headless --clean -l tests/run.lua list_format_spec
grep -nE 'vim\.(api|fn|system|notify|schedule)' lua/damnit/tree.lua lua/damnit/list_format.lua
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "refactor: build the subtask tree from dam's path"
```

Expected: both green, and the grep finds nothing.

---

### Task 18: The list buffer

`:Dam list [<view>]`, fed by `dam ls <query> --json`. The buffer, its folds, `<CR>`, `R` and `gd`
carry over; the quick edits arrive in Task 19.

**Files:**

- Create: `lua/damnit/list.lua`, `tests/list_spec.lua`, `tests/fixtures/full/ls.json`
- Modify: `plugin/damnit.lua`, `lua/damnit/init.lua`, `lua/damnit/keys.lua`

Start from `git show <rename sha>:lua/damnit/list.lua`, which already has the buffer, the fold table,
the cursor reading and the refresh-after-write rule.

**Interfaces:**

- Produces: `list.open(spec) -> integer buf`, `list.refresh()`, `list.current_spec() -> damnit.ListSpec?`,
  `list.object_under_cursor() -> table?`, `list.object_above_cursor() -> table?`,
  `list.toggle_fold()`, `list.fetch(spec, callback)`, `damnit.open(name)`, and
  `list.write(args, label)`, which is `actions.write` for the list: queue it, report a failure, and
  re-read the view on screen either way. Task 19's quick edits all go through it.

- [ ] **Step 1: Write the fixture**

`tests/fixtures/full/ls.json` is a JSON array of four wire objects: a parent at `work/parent/`, its
child at `work/parent/child/`, a task at `inbox/` with a due date and two labels, and one with a body
holding a location line (`damnit.nvim lua/damnit/status.lua:112`), which Task 22 reads back.

- [ ] **Step 2: Write the failing test**

Create `tests/list_spec.lua`:

```lua
-- The list buffer: what it asks dam for, what it draws, and what it refuses.

dofile(((arg[0]:match("(.*)/") or ".") .. "/../plugin/damnit.lua"))

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local damnit = require("damnit")
local queue = require("damnit.queue")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

---@param run fun(buf: integer, fake: damnit.FakeDam, notifications: string[])
---@param opts { views: table?, name: string?, fixtures: string?, exit: integer?, stderr: string? }?
local function with_list(run, opts)
  opts = opts or {}

  local fake = fake_dam.install({
    fixtures = opts.fixtures or (TESTS_DIR .. "/fixtures/full"),
    exit = opts.exit,
    stderr = opts.stderr,
  })
  queue.reset()
  damnit.options.views = opts.views or {}

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local buf = damnit.open(opts.name)
  fake_dam.settle(function()
    return queue.running() == nil
  end)

  local ok, err = pcall(run, buf, fake, notifications)

  vim.notify = real
  damnit.options.views = {}
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

return {
  ["asks dam for every open object and draws one line each"] = function()
    with_list(function(buf, fake)
      assert(vim.tbl_contains(fake_dam.argv_log(fake), "ls --json"), vim.inspect(fake_dam.argv_log(fake)))

      local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      assert(body:find("parent", 1, true), body)
      assert(body:find("child", 1, true), body)
    end)
  end,

  ["indents a child under the object whose path it extends"] = function()
    with_list(function(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local parent, child = nil, nil

      for index, line in ipairs(lines) do
        if line:find("parent", 1, true) then
          parent = index
        end
        if line:find("child", 1, true) then
          child = index
        end
      end

      assert(parent and child and child > parent, vim.inspect(lines))
      assert(#lines[child]:match("^%s*") > #lines[parent]:match("^%s*"), vim.inspect(lines))
    end)
  end,

  ["sends the declared query rather than the view's name"] = function()
    with_list(function(_, fake)
      assert(
        vim.tbl_contains(fake_dam.argv_log(fake), "ls due:today | overdue --json"),
        vim.inspect(fake_dam.argv_log(fake))
      )
    end, { views = { today = "due:today | overdue" }, name = "today" })
  end,

  ["reports dam's own wording for a name it cannot parse, and remembers it"] = function()
    with_list(function(_, fake, notifications)
      assert(notifications[#notifications] == "unexpected nonsense in query", vim.inspect(notifications))

      local before = #fake_dam.argv_log(fake)
      damnit.open("nonsense")

      assert(#fake_dam.argv_log(fake) == before, "the second attempt costs no call")
    end, {
      name = "nonsense",
      exit = 1,
      stderr = '{"error": {"kind": "parse", "rule": null, '
        .. '"message": "unexpected nonsense in query", "oids": []}}',
    })
  end,

  ["keeps a probed name when the failure said nothing about it"] = function()
    with_list(function(_, fake)
      local before = #fake_dam.argv_log(fake)
      damnit.open("today")

      assert(#fake_dam.argv_log(fake) > before, "a locked store must not refuse the name for the session")
    end, {
      name = "today",
      exit = 1,
      stderr = '{"error": {"kind": "store", "rule": null, '
        .. '"message": "the store is locked", "oids": []}}',
    })
  end,

  ["R re-reads the view, and za folds a subtree away"] = function()
    with_list(function(buf, fake)
      local before = #fake_dam.argv_log(fake)
      vim.api.nvim_feedkeys("R", "x", false)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)
      assert(fake_dam.argv_log(fake)[before + 1] == "ls --json", vim.inspect(fake_dam.argv_log(fake)))

      local full = vim.api.nvim_buf_line_count(buf)
      for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:find("parent", 1, true) then
          vim.api.nvim_win_set_cursor(0, { index, 0 })
          break
        end
      end

      vim.api.nvim_feedkeys("za", "x", false)

      -- A fold here means lines that were never drawn, not lines hidden.
      assert(vim.api.nvim_buf_line_count(buf) < full, "the child's line is gone")
    end)
  end,
}
```

- [ ] **Step 3: Write the module**

Bring `list.lua` across with these changes:

```lua
--- Ask dam for one view's objects.
---@param spec damnit.ListSpec
---@param callback fun(objects: table[]?, err: damnit.Error?)
function M.fetch(spec, callback)
  require("damnit.queue").submit({
    args = require("damnit.views").query_args(spec),
    label = "ls",
    on_done = function(objects, err)
      -- A bare name that is not a saved filter is parsed as query text, and
      -- a word with no colon is not a term, so dam answers `parse`. That is
      -- the one kind that says the name is a view in neither source: a locked
      -- store, a timeout or a cancel says nothing about it, and forgetting one
      -- has no expiry short of restarting Neovim. `refused` is left out
      -- deliberately, because a real saved filter naming a category the config
      -- has since dropped raises `unknown_category` while probing is still
      -- true, and forgetting that name would refuse a view that exists.
      if err and err.kind == "parse" and spec.probing then
        require("damnit.views").forget_filter(spec.title)
      end

      callback(objects, err)
    end,
  })
end
```

Everything else in the module keeps its shape: `open` resolves the spec through `damnit.views`, draws
through `list_format.render`, keeps the per-view fold table keyed by path rather than by task id, and
re-reads the view on screen after every write.

- [ ] **Step 4: Wire the command and the keymap function**

In `plugin/damnit.lua`:

```lua
  list = function(args)
    require("damnit").open(args[1])
  end,
```

and in `complete`, offer the declared view names after `list` and `pick`. Neovim calls a completion
function with the lead, the whole command line and the cursor position, so the subcommand is read off
the line rather than off a command table that is not in scope here:

```lua
---@param lead string what has been typed of the argument being completed
---@param line string the whole command line so far
---@return string[]
local function complete(lead, line)
  local typed = vim.split(vim.trim(line), "%s+")

  if #typed > 1 and (typed[2] == "list" or typed[2] == "pick") then
    return vim.tbl_filter(function(name)
      return vim.startswith(name, lead)
    end, require("damnit.views").declared())
  end

  local names = {}
  for name in pairs(SUBCOMMANDS) do
    if name ~= "" and vim.startswith(name, lead) then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  return names
end
```

In `lua/damnit/init.lua`, restore `M.open(name)` from the pre-strip commit, resolving through
`damnit.views` rather than through the deleted `M.view`.

- [ ] **Step 5: Run, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua list_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: list a dam view in a buffer"
```

---

### Task 19: The quick edits, and completing a parent

The list's seven surviving quick edits, plus the one place dam and Todoist differ most: dam refuses to
complete a parent rather than cascading, so the confirm becomes an explanation and a choice.

**Files:**

- Create: `lua/damnit/quick_edit.lua`, `tests/quick_edit_spec.lua`, `tests/done_spec.lua`
- Create: `tests/fixtures/full/done.json`, `tests/fixtures/full/new.json`
- Modify: `lua/damnit/list.lua`

Start from `git show <rename sha>:lua/damnit/quick_edit.lua` for the prompting and the label toggling,
and delete its `reopen`, `undo` and `forget` functions with their state.

**Interfaces:**

- Produces: `quick_edit.complete()`, `quick_edit.delete()`, `quick_edit.cycle_priority()`,
  `quick_edit.schedule()`, `quick_edit.labels()`, `quick_edit.move()`, `quick_edit.add()`,
  `quick_edit.indent()`, `quick_edit.promote()`, `quick_edit.reopen()` (the refusal),
  `quick_edit.blockers(err) -> string[]`, `quick_edit.attach(buf)`.

- [ ] **Step 1: Write the failing tests**

`tests/done_spec.lua` is the one that carries the design:

```lua
-- Completing a task, and what happens when dam refuses because something under
-- it is still open.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local quick_edit = require("damnit.quick_edit")

return {
  ["reads the blockers dam named in the refusal's oids"] = function()
    local blockers = quick_edit.blockers({
      kind = "refused",
      rule = "blocked",
      message = "98d8780 cannot be completed: child a9db854 is open",
      oids = {
        "98d878013fb0e026d37170e7ceed6707192ae99a",
        "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77",
        "660a08d1c4b9e8f0a2d3c5b7e9f1a3c5d7e9f1b3",
      },
    })

    assert(vim.deep_equal(blockers, { "a9db854", "660a08d" }), vim.inspect(blockers))
  end,

  ["offers to complete it anyway, and sends --force when that is chosen"] = function()
    -- The fake exits 4 on the first done and 0 on the second, which is what a
    -- forced completion does.
    local fake = fake_dam.install({
      exit = 4,
      stderr = '{"error": {"kind": "refused", "rule": "blocked", "message": "98d8780 cannot be completed:'
        .. '\\n  child a9db854 is open\\nuse --force to complete it anyway, or --force --interactive to '
        .. 'decide what happens to them", "oids": ["98d878013fb0e026d37170e7ceed6707192ae99a", '
        .. '"a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77"]}}',
    })

    local chosen = nil
    local real = vim.ui.select
    vim.ui.select = function(items, opts, on_choice)
      chosen = opts.prompt
      on_choice(items[1], 1)
    end

    local object = { oid = "98d8780134fb0e026d37170e7ceed6707192ae99", subject = "file taxes" }
    quick_edit.send_done(object, false)

    fake_dam.settle(function()
      return #fake_dam.argv_log(fake) >= 3
    end)

    vim.ui.select = real
    local log = fake_dam.argv_log(fake)
    fake_dam.remove(fake)

    assert(log[2] == "done 98d8780134fb0e026d37170e7ceed6707192ae99 --json", vim.inspect(log))
    assert(log[3] == "done 98d8780134fb0e026d37170e7ceed6707192ae99 --force --json", vim.inspect(log))
    assert(chosen:find("a9db854", 1, true), tostring(chosen))
  end,

  ["recognises the rule for a question no machine format can answer"] = function()
    local said = quick_edit.interactive_refusal({ kind = "refused", rule = "needs_an_answer" }, "98d8780")

    assert(
      said == "dam is configured to ask what happens to the children; run dam done 98d8780 --force --interactive in a terminal",
      said
    )
  end,

  ["reports a recurring task as rolled forward rather than as done"] = function()
    local fake = fake_dam.install()
    vim.env.DAMNIT_TEST_FIXTURES = fake.dir

    local file = assert(io.open(fake.dir .. "/done.json", "w"))
    file:write('{"oid": "98d8780134fb0e026d37170e7ceed6707192ae99", "rolled_forward": "2026-09-27"}\n')
    file:close()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    quick_edit.send_done({ oid = "98d8780134fb0e026d37170e7ceed6707192ae99", subject = "water the plants" }, false)

    fake_dam.settle(function()
      return #said > 0
    end)

    vim.notify = real
    fake_dam.remove(fake)

    assert(said[1] == "damnit.nvim: rolled forward to 2026-09-27", said[1])
    for _, line in ipairs(said) do
      assert(not line:find("completed", 1, true), "a rolled forward task was not completed: " .. line)
    end
  end,
}
```

`tests/quick_edit_spec.lua` covers the other six keys by the argv each sends. It reuses `with_list`
from `list_spec`, so lift that helper into `tests/helpers/list_buffer.lua` in this task and have both
specs `dofile` it.

```lua
local list_buffer = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/list_buffer.lua")
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local quick_edit = require("damnit.quick_edit")

--- Press a key on the first object in the list and hand back what dam was sent.
---@param key string
---@param answer string|nil what vim.ui.input or vim.ui.select answers with
---@return string sent
local function pressed(key, answer)
  local sent = nil

  list_buffer.with(function(buf, fake)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    local before = #fake_dam.argv_log(fake)

    local input, select = vim.ui.input, vim.ui.select
    vim.ui.input = function(_, on_answer)
      on_answer(answer)
    end
    vim.ui.select = function(items, _, on_choice)
      for index, item in ipairs(items) do
        if tostring(item) == answer then
          return on_choice(item, index)
        end
      end

      on_choice(items[1], 1)
    end

    vim.api.nvim_feedkeys(key, "x", false)

    fake_dam.settle(function()
      return #fake_dam.argv_log(fake) > before
    end)

    vim.ui.input, vim.ui.select = input, select
    sent = fake_dam.argv_log(fake)[before + 1]
  end)

  return sent
end

return {
  ["dd removes the object after a confirm"] = function()
    local sent = pressed("dd", "y")

    assert(sent:find("^rm "), sent)
    assert(sent:find("--json", 1, true), sent)
  end,

  ["p cycles the priority 4, 3, 2, 1, 4"] = function()
    assert(quick_edit.cycled(4) == 3)
    assert(quick_edit.cycled(3) == 2)
    assert(quick_edit.cycled(2) == 1)
    assert(quick_edit.cycled(1) == 4)

    local sent = pressed("p", nil)
    assert(sent:find("-p ", 1, true), sent)
  end,

  ["s sends the typed line unparsed, because dam parses a due string"] = function()
    local sent = pressed("s", "next tuesday at 9")

    assert(sent:find("--due next tuesday at 9", 1, true), sent)
  end,

  ["l adds a label it does not have and removes one it does"] = function()
    local added = pressed("l", "slow")
    assert(added:find("--label slow", 1, true), added)

    local removed = pressed("l", "home")
    assert(removed:find("--unlabel home", 1, true), removed)
  end,

  ["m moves the object to a path chosen from the paths in view"] = function()
    local sent = pressed("m", "work/parent/")

    assert(sent:find("^mv "), sent)
    assert(sent:find("work/parent/", 1, true), sent)
  end,

  ["a creates one under the path the cursor is in"] = function()
    local sent = pressed("a", "buy stamps")

    assert(sent:find("^new buy stamps ", 1, true), sent)
    assert(sent:find("--path ", 1, true), sent)
  end,
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `nvim --headless --clean -l tests/run.lua done_spec`
Expected: four FAILs, `module 'damnit.quick_edit' not found`.

- [ ] **Step 3: Write the completion path**

```lua
--- The objects blocking a completion, as dam named them: every oid after the
--- first, which is the task itself.
---@param err damnit.Error
---@return string[]
function M.blockers(err)
  local found = {}

  for index, oid in ipairs(err.oids or {}) do
    if index > 1 then
      found[#found + 1] = tostring(oid):sub(1, 7)
    end
  end

  return found
end

--- The sentence for dam being configured to ask a question no client can answer.
---@param err damnit.Error
---@param oid string
---@return string?
function M.interactive_refusal(err, oid)
  if err.rule ~= "needs_an_answer" then
    return nil
  end

  return ("dam is configured to ask what happens to the children; run dam done %s --force --interactive in a terminal"):format(
    oid:sub(1, 7)
  )
end

--- Complete the object under the cursor.
---
--- dam refuses while a child or a dependency is open and lists the blockers, so
--- the plugin shows them and offers the one disposition it can reach without a
--- terminal. Task 31 adds the other two once dam takes them as flags.
function M.complete()
  local object = require("damnit.list").object_under_cursor()
  if not object then
    return
  end

  M.send_done(object, false)
end

---@param object table
---@param force boolean
function M.send_done(object, force)
  local args = { "done", object.oid }

  if force then
    args[#args + 1] = "--force"
  end

  args[#args + 1] = "--json"

  require("damnit.queue").submit({
    args = args,
    label = "done",
    on_done = function(report, err)
      if not err then
        -- Completing a recurring task does not complete it, and the two are
        -- different outcomes.
        if report and report.rolled_forward then
          message.say(("rolled forward to %s"):format(tostring(report.rolled_forward)))
        end

        return require("damnit.list").refresh()
      end

      local interactive = M.interactive_refusal(err, object.oid)
      if interactive then
        return message.warn(interactive)
      end

      if err.kind ~= "refused" or force then
        return message.report(err)
      end

      local blockers = M.blockers(err)
      vim.ui.select({ "Complete it anyway, keeping the children where they are", "Cancel" }, {
        prompt = ("%s is blocked by: %s"):format(object.oid:sub(1, 7), table.concat(blockers, ", ")),
      }, function(choice)
        if choice and vim.startswith(choice, "Complete") then
          M.send_done(object, true)
        end
      end)
    end,
  })
end

--- dam has no verb that reopens a completed task, so `X` says so rather than
--- pretending. Task 29 replaces this with `dam edit <oid> --undone`.
function M.reopen()
  message.warn("dam has no verb that reopens a completed task; edit it in a terminal")
end
```

The rolled-forward field name is the one thing here read off dam's report rather than its prose.
Confirm it with `dam done <oid of a recurring task> --json | jq .` and correct the key if it differs.

- [ ] **Step 4: Write the other six, bind them, run, lint and commit**

Each is the existing function with its API call replaced by `require("damnit.list").write(args)`, which
is `actions.write` for the list: queue it, report a failure, re-read the view on screen.

```bash
nvim --headless --clean -l tests/run.lua done_spec
nvim --headless --clean -l tests/run.lua quick_edit_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: quick edits on the list, including dam's blocked completion"
```

---

### Task 20: The picker

`:Dam pick [<view>]`, fzf-lua when it loads and `vim.ui.select` otherwise. Unchanged in shape; the
entries carry dam's fields.

**Files:**

- Create: `lua/damnit/picker.lua`, `tests/picker_spec.lua`
- Modify: `plugin/damnit.lua`, `lua/damnit/init.lua`

Start from `git show <rename sha>:lua/damnit/picker.lua`, which already has the fzf-lua detection, the
`opts.picker` three-way choice and the `<C-x>` action.

**Interfaces:**

- Produces: `picker.line(object) -> string`, `picker.entries(objects) -> { text, oid }[]`,
  `picker.pick(name)`, `picker.open_entry(entry)`, `picker.complete_entry(entry)`,
  `damnit.pick(name)`.

- [ ] **Step 1: Write the failing test**

Create `tests/picker_spec.lua` with three cases:

```lua
local picker = require("damnit.picker")

local OBJECT = {
  oid = "78b8950b02735107aa608659dcf19f6f50adfeb1",
  subject = "buy oat milk",
  path = "inbox/",
  labels = { "errand", "home" },
  task = { priority = 1, due = "2026-09-25" },
}

return {
  ["puts every field worth typing at on the line"] = function()
    local line = picker.line(OBJECT)

    for _, wanted in ipairs({ "buy oat milk", "2026-09-25", "p1", "errand", "home", "inbox/" }) do
      assert(line:find(wanted, 1, true), ("%q is missing from %q"):format(wanted, line))
    end
  end,

  ["carries the oid beside the line rather than in it"] = function()
    local entries = picker.entries({ OBJECT })

    assert(entries[1].oid == OBJECT.oid, entries[1].oid)
    assert(not entries[1].text:find(OBJECT.oid, 1, true), "forty characters of noise stay out of the line")
  end,

  ["follows the screen when it is given no name"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    queue.reset()
    damnit.options.views = { today = "due:today | overdue" }

    local buf = damnit.open("today")
    fake_dam.settle(function()
      return vim.api.nvim_buf_line_count(buf) > 1
    end)

    local before = #fake_dam.argv_log(fake)
    picker.pick(nil)
    fake_dam.settle(function()
      return #fake_dam.argv_log(fake) > before
    end)

    assert(
      fake_dam.argv_log(fake)[before + 1] == "ls due:today | overdue --json",
      vim.inspect(fake_dam.argv_log(fake))
    )

    vim.cmd("silent! %bwipeout!")
    local alone = #fake_dam.argv_log(fake)
    picker.pick(nil)
    fake_dam.settle(function()
      return #fake_dam.argv_log(fake) > alone
    end)

    assert(fake_dam.argv_log(fake)[alone + 1] == "ls --json", vim.inspect(fake_dam.argv_log(fake)))

    damnit.options.views = {}
    queue.reset()
    fake_dam.remove(fake)
  end,
}
```

- [ ] **Step 2: Run, write the module, run again**

The module is the old one with `content` becoming `subject`, the project and section names becoming
`path`, the priority badge reversing, and the fetch going through `list.fetch`.

- [ ] **Step 3: Wire the command and commit**

```lua
  pick = function(args)
    require("damnit").pick(args[1])
  end,
```

```bash
nvim --headless --clean -l tests/run.lua picker_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: search the dam objects with fzf-lua or vim.ui.select"
```

---

### Task 21: The completed history

`:Dam done` is one local query rendered flat, newest first. The whole paging apparatus is already gone
with `completed_history.lua`; this task makes sure nothing brings it back.

**Files:**

- Modify: `lua/damnit/list.lua` (a flat spec), `plugin/damnit.lua`, `lua/damnit/init.lua`
- Create: `tests/history_spec.lua`, `tests/fixtures/done/ls.json`

**Interfaces:**

- Produces: `damnit.completed() -> integer buf`, and `damnit.ListSpec` gains `flat: boolean?`, which
  `list_format.render` reads to skip the tree.

- [ ] **Step 1: Write the failing test**

Create `tests/history_spec.lua`:

```lua
local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local damnit = require("damnit")
local queue = require("damnit.queue")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

return {
  ["asks dam for the done objects in one call"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/done" })
    queue.reset()

    local buf = damnit.completed()
    fake_dam.settle(function()
      return vim.api.nvim_buf_line_count(buf) > 1
    end)

    local log = fake_dam.argv_log(fake)
    local calls = 0
    for _, line in ipairs(log) do
      if vim.startswith(line, "ls ") then
        calls = calls + 1
      end
    end

    vim.cmd("silent! %bwipeout!")
    queue.reset()
    fake_dam.remove(fake)

    assert(vim.tbl_contains(log, "ls done --json"), vim.inspect(log))
    assert(calls == 1, "the whole history is one query, so there is nothing to page")
  end,

  ["draws it flat, in the order dam answered"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/done" })
    queue.reset()

    local buf = damnit.completed()
    fake_dam.settle(function()
      return vim.api.nvim_buf_line_count(buf) > 1
    end)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    vim.cmd("silent! %bwipeout!")
    queue.reset()
    fake_dam.remove(fake)

    -- The fixture's first object is the most recently completed one, and the
    -- history has no tree: nothing is drawn under anything.
    assert(lines[3]:find("paid the rent", 1, true), vim.inspect(lines))

    for index = 3, #lines do
      if lines[index] ~= "" then
        assert(not lines[index]:match("^%s%s%s+%S"), "no line is indented: " .. lines[index])
      end
    end
  end,

  ["says dam has no verb that reopens one"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/done" })
    queue.reset()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    local buf = damnit.completed()
    fake_dam.settle(function()
      return vim.api.nvim_buf_line_count(buf) > 1
    end)

    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    local before = #fake_dam.argv_log(fake)
    vim.api.nvim_feedkeys("u", "x", false)

    vim.notify = real
    local after = #fake_dam.argv_log(fake)

    vim.cmd("silent! %bwipeout!")
    queue.reset()
    fake_dam.remove(fake)

    assert(after == before, "nothing was sent")
    assert(
      said[#said] == "damnit.nvim: dam has no verb that reopens a completed task; edit it in a terminal",
      vim.inspect(said)
    )
  end,
}
```

The fixture `tests/fixtures/done/ls.json` holds three completed objects, the first of them
`paid the rent`, so the second case reads a real subject rather than a position.

- [ ] **Step 2: Add the flat spec and the command**

```lua
  done = function()
    require("damnit").completed()
  end,
```

```lua
--- The completed history, newest first. One local query: dam holds the whole
--- history, so there is nothing to page.
---@return integer buf
function M.completed()
  return require("damnit.list").open({ title = "completed", query = "done", flat = true })
end
```

- [ ] **Step 3: Run, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua history_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: read the completed history in one query"
```

---

### Task 22: Capture from code, and jumping back to it

`:Dam capture` writes the location into `body`, and `gd` reads it back out of `body`.

**Files:**

- Create: `lua/damnit/capture.lua`, `tests/capture_spec.lua`, `lua/damnit/location_edit.lua`,
  `tests/location_edit_spec.lua`
- Modify: `lua/damnit/location.lua`, `tests/location_spec.lua`, `lua/damnit/list.lua`,
  `plugin/damnit.lua`

Start from the two files as they stand. `location.lua` needs two changes. Its doc comment says
"description", and the field is now `body`. And its two editor-side functions, `of_buffer` and
`jump`, move into `location_edit.lua`, which is what makes the file match the purity constraint the
Global Constraints and Task 27's grep both hold it to: every `vim.api`, `vim.fn` and `vim.notify`
call in the file today is inside one of those two. Its parsing is text parsing and is unchanged.

**Interfaces:**

- Produces: `capture.content(lines) -> string`, `capture.create(content, location)`,
  `capture.capture(range)`, `location.parse(body)`, `location.describe(location)`,
  `location_edit.of_buffer(buf, line)`, `location_edit.jump(location)`.

- [ ] **Step 1: Move the editor half of a location into its own module**

Create `lua/damnit/location_edit.lua` with the three functions that reach the editor, lifted from
`location.lua` unchanged apart from the module header:

```lua
-- Reading a location off the buffer, and opening the file one names.
--
-- `location.lua` is the text half and calls nothing on the editor, which is
-- what lets it be tested without one. Every window, buffer and file system
-- call of a location lives here instead.

local message = require("damnit.message")

local M = {}

---@param path string
---@return string? root normalized, when the path is inside a repository
local function repository_root(path)
  local root = vim.fs.root(path, ".git")

  return root and vim.fs.normalize(root) or nil
end

--- The location a buffer and a line are, or nil when there is nowhere to point.
---
--- A buffer with no name, a scratch buffer and a directory listing all answer
--- nil: none of them is a file with a line in it, and a capture from one simply
--- carries no location.
---@param buf integer? defaults to the current buffer
---@param line integer? defaults to the cursor's line
---@return damnit.Location? location
function M.of_buffer(buf, line)
  buf = buf or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1]

  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" or vim.fn.isdirectory(name) == 1 then
    return nil
  end

  local path = vim.fs.normalize(name)
  local root = repository_root(path)

  if root and vim.startswith(path, root .. "/") then
    return { repo = vim.fs.basename(root), path = path:sub(#root + 2), line = line }
  end

  return { path = vim.fs.basename(path), line = line }
end

---@param text string
---@return false
local function refuse(text)
  message.warn(text)

  return false
end

--- Open the file a location names and put the cursor on its line.
---
--- The path is resolved against the repository the editor is in, which is the
--- only base this plugin has: the body carries no absolute path, on purpose. A
--- location from another repository, a file that has since gone and a line past
--- the end of the file are each reported and none of them raises.
---@param location damnit.Location?
---@return boolean jumped
function M.jump(location)
  if not location then
    return refuse("this task has no location in its body")
  end

  local cwd = vim.fs.normalize(vim.uv.cwd() or ".")
  local base = repository_root(cwd) or cwd
  local here = vim.fs.basename(base)

  if location.repo and location.repo ~= here then
    return refuse(("this task points into %s, and %s is what is open here"):format(location.repo, here))
  end

  local path = vim.fs.joinpath(base, location.path)
  if vim.fn.filereadable(path) == 0 then
    return refuse(("there is no file at %s"):format(location.path))
  end

  vim.cmd.edit(vim.fn.fnameescape(path))

  local last = vim.api.nvim_buf_line_count(0)
  local line = math.min(location.line, last)
  vim.api.nvim_win_set_cursor(0, { line, 0 })

  if line ~= location.line then
    -- The file is open where it can be read; the line moved out from under the
    -- task, which is worth saying rather than landing silently.
    message.warn(("%s has %d lines, so this is the last one"):format(location.path, last))
  end

  return true
end

return M
```

Delete `repository_root`, `of_buffer`, `refuse` and `jump` from `location.lua`, along with
the `local message = require("damnit.message")` line at its head, which only those two used. What is
left is `ICON`, the `damnit.Location` class, `describe` and `parse`, and it calls nothing on `vim`
at all. Its header changes in the same edit, since it no longer opens anything and the field is now
`body`:

```lua
-- Where in the code a task came from, as one line of its body.
--
-- The line is `<repository> <path>:<line>`, and `<path>:<line>` alone when the
-- file is in no repository. It is written to be read by a person on their
-- phone and parsed back by `gd`, in that order of importance.
--
-- THE PATH IS ALWAYS RELATIVE to the repository root, and a file outside a
-- repository goes out as its own name alone. A body syncs to a remote and to
-- every device that pulls it, so an absolute path would put the home directory
-- of the machine that captured it there.
--
-- Parsing a body back is parsing text a person can edit on their phone, so
-- every answer here is either a location or nil. Opening what one names is
-- `location_edit`, which is where the editor calls live.
```

`M.parse`'s own `---@param description string?` becomes `---@param body string?` and its summary
line becomes "The location a body holds, or nil when no line of it is one."

- [ ] **Step 2: Split the spec along the same line**

Move the five jump cases and the two helpers they use into a new `tests/location_edit_spec.lua`,
which starts:

```lua
-- Getting back to the code a task came from.
--
-- A body is text a person can edit on their phone, so these cases are mostly
-- about what `jump` does with one it cannot use. Nothing here reaches a task
-- store: a location is a string, and the files are made by the spec.

local location_edit = require("damnit.location_edit")
```

The helpers move verbatim. In `jump_from`, `pcall(location.jump, parsed)` becomes
`pcall(location_edit.jump, parsed)`. The five cases that move are the ones naming `jump`:

```
jumps to the file and the line
refuses a task whose description holds no location
refuses a location whose file is gone
refuses a location captured in another repository, and names both
says so when the line is past the end, and lands on the last one
```

The second of those asserts on the word "description", which is now "body" in both the module and
the case name:

```lua
  ["refuses a task whose body holds no location"] = function()
    local root = repository(3)
    local jumped, said = jump_from(root, nil)

    assert(jumped == false, "a task with no location was jumped to")
    assert(#said == 1 and said[1]:find("no location in its body", 1, true), vim.inspect(said))
  end,
```

`tests/location_spec.lua` keeps its five parse and describe cases and loses both helpers, which no
case left in it calls. Its own header loses the sentence about `jump`.

- [ ] **Step 3: Point the list's `gd` at the new module**

`lua/damnit/list.lua` is the only caller of `jump` in the tree. In
`M.jump_to_location_under_cursor`:

```lua
  require("damnit.location_edit").jump(locations[line])
```

- [ ] **Step 4: Run the split, prove the purity, and commit**

Run: `nvim --headless --clean -l tests/run.lua location_spec`
Expected: the five parse and describe cases pass.

Run: `nvim --headless --clean -l tests/run.lua location_edit_spec`
Expected: the same five jump cases pass, with the same wording, under the new module name.

Run: `grep -nE 'vim\.(api|fn|system|notify|schedule)' lua/damnit/location.lua`
Expected: no output, exit 1. This is the gate Task 27 installs, run early against the one file that
could not pass it before.

```bash
nvim --headless --clean -l tests/run.lua
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "refactor: keep the editor calls of a location out of the pure half"
```

- [ ] **Step 5: Write the failing test**

Create `tests/capture_spec.lua`:

```lua
local capture = require("damnit.capture")

return {
  ["builds the argv dam new takes, with the location in the body"] = function()
    local args = capture.args("buy oat milk", { repo = "damnit.nvim", path = "lua/damnit/status.lua", line = 112 })

    assert(
      vim.deep_equal(args, {
        "new",
        "buy oat milk",
        "--path",
        "inbox/",
        "--body",
        "damnit.nvim lua/damnit/status.lua:112",
        "--json",
      }),
      vim.inspect(args)
    )
  end,

  ["leaves the body out when the buffer has no location"] = function()
    local args = capture.args("buy oat milk", nil)

    assert(vim.deep_equal(args, { "new", "buy oat milk", "--path", "inbox/", "--json" }), vim.inspect(args))
  end,

  ["joins a visual selection into one subject"] = function()
    assert(capture.content({ "  buy", "  oat milk  " }) == "buy oat milk", capture.content({ "  buy", "  oat milk  " }))
  end,
}
```

Add one case to `tests/location_spec.lua` proving `location.parse` reads the same text back out of a
body holding a note above it.

- [ ] **Step 6: Write `capture.args` and bring the rest across**

```lua
--- The `dam new` argv one capture becomes.
---
--- The location is relative and never absolute: a body syncs to a remote and
--- onto a phone.
---@param content string
---@param location damnit.Location?
---@return string[]
function M.args(content, location)
  local args = { "new", content, "--path", "inbox/" }

  if location then
    vim.list_extend(args, { "--body", require("damnit.location").describe(location) })
  end

  args[#args + 1] = "--json"

  return args
end
```

- [ ] **Step 7: Wire the command, run, lint and commit**

```lua
  capture = function(_, cmd)
    local selection = cmd.range > 0 and { line1 = cmd.line1, line2 = cmd.line2 } or nil

    require("damnit.capture").capture(selection)
  end,
```

```bash
nvim --headless --clean -l tests/run.lua capture_spec
nvim --headless --clean -l tests/run.lua location_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: capture a task from the code and jump back to it"
```

---

### Task 23: Sending an object to the agent

`S` in the list. The delivery path is unchanged; the brief's fields are dam's, and the hand-off record
is dropped because dam has no comments.

**Files:**

- Create: `lua/damnit/send.lua`, `tests/send_spec.lua`

Start from `git show <rename sha>:lua/damnit/send.lua`. The herdr delivery, the agent choice, the
clipboard fallback and the four failure cases all come across unchanged.

**Interfaces:**

- Produces: `send.brief(object, note) -> string`, `send.pasted(brief)`, `send.agent_in(listing, workspace, me)`,
  `send.hand_off(object, note, host)`, `send.host()`, `send.send()`.

- [ ] **Step 1: Write the failing test**

Rewrite `tests/send_spec.lua`'s brief cases:

```lua
return {
  ["writes dam's own fields, and leaves out what the object has none of"] = function()
    local brief = send.brief({
      oid = "78b8950b02735107aa608659dcf19f6f50adfeb1",
      subject = "file taxes",
      body = "receipts are in the drawer",
      path = "home/finances/",
      labels = { "home", "slow" },
      task = { priority = 1, due = "2026-09-20" },
    }, "start with the receipts")

    assert(brief:find("dam task: file taxes", 1, true), brief)
    assert(brief:find("oid: 78b8950", 1, true), "seven characters, which is what an agent types")
    assert(not brief:find("78b8950b027", 1, true), "never the whole forty")
    assert(brief:find("path: home/finances/", 1, true), brief)
    assert(brief:find("priority: p1", 1, true), brief)
    assert(brief:find("labels: home, slow", 1, true), brief)
    assert(brief:find("receipts are in the drawer", 1, true), brief)
    assert(brief:find("note: start with the receipts", 1, true), brief)
  end,

  ["leaves out a field the object has nothing for"] = function()
    local brief = send.brief({ oid = "78b8950b02735107aa608659dcf19f6f50adfeb1", subject = "x", path = "inbox/" }, nil)

    assert(not brief:find("due:", 1, true), brief)
    assert(not brief:find("labels:", 1, true), brief)
  end,

  ["every notification ends by saying no record was written"] = function()
    local OBJECT = { oid = "78b8950b02735107aa608659dcf19f6f50adfeb1", subject = "file taxes", path = "inbox/" }

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    -- dam has no comments, so a hand-off leaves no trace in the store. Both
    -- paths say so, and neither pretends a record exists.
    send.hand_off(OBJECT, nil, { kind = "herdr", send = function() return true end, focus = function() return true end })
    send.hand_off(OBJECT, nil, { kind = "herdr", send = function() return false, "no agent pane" end })

    vim.notify = real

    assert(#said == 2, vim.inspect(said))
    for _, line in ipairs(said) do
      assert(line:find("no hand-off record written", 1, true), line)
    end
  end,
}
```

- [ ] **Step 2: Write the brief, keep the delivery, run, lint and commit**

The `store:` line is the store as the window's header shows it, so it reuses the same helper rather
than a second one. The brief carries no URL, because a dam object is local.

```bash
nvim --headless --clean -l tests/run.lua send_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: hand a dam object to the agent pane"
```

---

### Task 24: The sidebar

Unchanged behaviour on a new source. Restore the file and change the two lines that name a view.

**Files:**

- Create: `lua/damnit/sidebar.lua`, `tests/sidebar_spec.lua`
- Modify: `plugin/damnit.lua`, `lua/damnit/init.lua`, `lua/damnit/location_edit.lua`,
  `tests/location_edit_spec.lua`

```bash
git show <rename sha>:lua/damnit/sidebar.lua > lua/damnit/sidebar.lua
git show <rename sha>:tests/sidebar_spec.lua > tests/sidebar_spec.lua
```

**Interfaces:**

- Produces: `sidebar.toggle()`, `sidebar.open()`, `sidebar.close()`, `sidebar.window()`,
  `damnit.toggle()`.

- [ ] **Step 1: Run the restored spec and watch it fail**

Run: `nvim --headless --clean -l tests/run.lua sidebar_spec`
Expected: FAILs where it resolves a view through the deleted `todoist.view`.

- [ ] **Step 2: Change the two lines**

`sidebar.open` resolves `opts.sidebar.view` through `require("damnit.views").resolve`, and refuses
before the split is made when the name is in neither source. `winfixwidth`, `winfixheight`,
`winfixbuf`, the `WinNew` and `WinResized` autocommands and the per-tabpage window-local flag are
untouched.

- [ ] **Step 3: Give the jump its way out of a fixed window again**

`leave_fixed_window` is the sidebar's, but its only caller is not: it sits in
`location_edit.jump`, which Task 2 stripped of the call when it deleted `sidebar.lua`. The restore
above cannot bring a caller back into a file the plan kept, so add it by hand, directly above the
`vim.cmd.edit` line in `lua/damnit/location_edit.lua`:

```lua
  require("damnit.sidebar").leave_fixed_window()
  vim.cmd.edit(vim.fn.fnameescape(path))
```

Without it, `gd` inside the sidebar hits `winfixbuf` and the `:edit` fails instead of opening the
file in a window that can hold it.

The require stays inside the function. `sidebar.lua` registers its `WinNew` and `WinResized`
autocommand at file scope, so requiring it at the head of `location_edit.lua` would install the
sidebar's width machinery in a session that only ever parsed a line of text.

That lazy require is resolved after `jump` has already changed the tabpage's directory, and the
runner's `package.path` is relative to where the run started, so `tests/location_edit_spec.lua`
needs the module loaded before any case moves. Add it below the spec's own require:

```lua
-- A jump changes the tabpage's directory, and the runner's `package.path` is
-- relative to where the run started, so everything a jump reaches is loaded
-- before any case moves.
require("damnit.sidebar")
```

Run: `nvim --headless --clean -l tests/run.lua location_edit_spec`
Expected: the five jump cases still pass. Each opens a tabpage with no sidebar in it, so
`leave_fixed_window` returns at its first line.

- [ ] **Step 4: Wire the command, run, lint and commit**

```lua
  toggle = function()
    require("damnit.sidebar").toggle()
  end,
```

```bash
nvim --headless --clean -l tests/run.lua sidebar_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: keep a dam view beside your work in the sidebar"
```

---

### Task 25: The statusline and the due reminders

One poller behind both, fed by `dam ls`. Two additions: a running operation takes the statusline slot,
and `dam !` replaces a stale count on failure.

**Files:**

- Create: `lua/damnit/poll.lua`, `tests/poll_spec.lua`
- Modify: `lua/damnit/due.lua`, `tests/due_spec.lua`, `lua/damnit/init.lua`

Start from `git show <rename sha>:lua/damnit/status.lua`. `due.lua` changes only where it reads the due
value: dam's `due` is a date or a datetime as text, so the plugin tells them apart by whether the
string carries a time.

**Interfaces:**

- Produces: `poll.status() -> string`, `poll.counts()`, `poll.apply(objects, err)`, `poll.refresh()`,
  `poll.start()`, `poll.stop()`, `poll.running() -> boolean`, `damnit.status()`.

- [ ] **Step 1: Write the failing test**

Create `tests/poll_spec.lua` with five cases, driving `poll.apply` directly so no timer is involved:

```lua
local poll = require("damnit.poll")

local function object(oid, due)
  return { oid = oid, subject = "x", path = "inbox/", task = { done = false, due = due } }
end

return {
  ["counts what is due and what is overdue"] = function()
    poll.apply({ object("aaaa1111", "2026-09-20"), object("bbbb2222", "2026-09-19") }, nil)

    assert(poll.status() == "1 due, 1 overdue", poll.status())
  end,

  ["says dam ! rather than leaving a stale count standing"] = function()
    poll.apply(nil, { kind = "error", code = 1, message = "storage: the store is locked" })

    assert(poll.status() == "dam !", poll.status())
  end,

  ["draws nothing at all when nothing is due"] = function()
    poll.apply({}, nil)

    assert(poll.status() == "", poll.status())
  end,

  ["shows the running operation instead of the count"] = function()
    local fake = fake_dam.install({ sleep = "0.3" })
    queue.reset()
    poll.apply({ object("aaaa1111", "2026-09-20") }, nil)

    queue.submit({ args = { "push", "--json" }, label = "push todoist", verb = "push", network = true })

    local shown = poll.status()

    fake_dam.settle(function()
      return queue.running() == nil
    end, 3000)
    queue.reset()
    fake_dam.remove(fake)

    -- A push in flight is worth the slot more than a count that has not moved,
    -- and it is how a push started from a window that was then closed stays
    -- visible.
    assert(shown:find("dam: push todoist", 1, true), shown)
    assert(shown:find("s", 1, true), shown)
  end,

  ["says nothing about what was already overdue when the first fetch lands"] = function()
    require("damnit").options.reminders = true
    poll.stop()

    local said = {}
    local real = vim.notify
    vim.notify = function(text)
      table.insert(said, text)
    end

    local past = { oid = "cccc3333", subject = "stand up", path = "inbox/", task = { due = "2000-01-01T09:00:00" } }

    poll.apply({ past }, nil)
    local after_first = #said

    poll.apply({ past, { oid = "dddd4444", subject = "sit down", path = "inbox/", task = { due = "2000-01-01T10:00:00" } } }, nil)

    vim.notify = real
    require("damnit").options.reminders = false
    poll.stop()

    -- Opening the editor in the evening does not replay the morning.
    assert(after_first == 0, vim.inspect(said))
    assert(#said == 1, vim.inspect(said))
    assert(said[1]:find("sit down", 1, true), said[1])
  end,
}
```

- [ ] **Step 2: Write the module**

The fetch is `queue.submit({ args = { "ls", "due:today | overdue", "--json" }, label = "ls" })`, quiet
on failure, on a `vim.uv` timer every `opts.refresh_interval` seconds. One poller, started by the first
`status()` or by `setup` when reminders are on, stopped on `VimLeavePre`.

```lua
--- The statusline string. Called on every redraw, so it does no work.
---@return string
function M.status()
  M.start()

  local running = require("damnit.queue").running()
  if running then
    return ("dam: %s %.1fs"):format(running.label, running.elapsed)
  end

  if state == "cold" then
    return ""
  end

  return line
end
```

- [ ] **Step 3: Run, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua poll_spec
nvim --headless --clean -l tests/run.lua due_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: poll dam for the statusline count and the due reminders"
```

---

### Task 26: `:checkhealth damnit`

Eight checks. It reports nothing about any credential's value, because it never sees one.

**Files:**

- Create: `lua/damnit/health.lua`, `tests/health_spec.lua`

Start from `git show <rename sha>:lua/damnit/health.lua` for the `vim.wait` helper, which is the one
place in this plugin where waiting is correct.

**Interfaces:**

- Produces: `health.check()`, `health.settle(start) -> boolean, any?, any?`.

- [ ] **Step 1: Write the failing test**

Create `tests/health_spec.lua` with three cases, each capturing `vim.health.ok`, `.warn` and `.error`
into a list:

```lua
-- :checkhealth damnit, and the one credential warning that is worth more before
-- the first push than after it.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local health = require("damnit.health")

local TESTS_DIR = arg[0]:match("(.*)/") or "."

---@param run fun(): nil
---@return { level: string, text: string }[]
local function report(run)
  local lines = {}
  local real = { ok = vim.health.ok, warn = vim.health.warn, error = vim.health.error, start = vim.health.start }

  for _, level in ipairs({ "ok", "warn", "error", "start" }) do
    vim.health[level] = function(text)
      table.insert(lines, { level = level, text = tostring(text) })
    end
  end

  local outcome, err = pcall(run)

  for _, level in ipairs({ "ok", "warn", "error", "start" }) do
    vim.health[level] = real[level]
  end

  assert(outcome, err)

  return lines
end

---@param lines { level: string, text: string }[]
---@param level string
---@param needle string
---@return boolean
local function said(lines, level, needle)
  for _, line in ipairs(lines) do
    if line.level == level and line.text:find(needle, 1, true) then
      return true
    end
  end

  return false
end

return {
  ["reports dam, its version and the supported range"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
    local lines = report(health.check)
    fake_dam.remove(fake)

    assert(said(lines, "ok", "dam 0.1.0"), vim.inspect(lines))
    assert(said(lines, "ok", ">=0.1.0 <0.2.0"), vim.inspect(lines))
    assert(said(lines, "ok", "todoist"), "one line per configured remote")

    for _, line in ipairs(lines) do
      assert(not line.text:lower():find("token", 1, true), "the health check never sees a credential")
    end
  end,

  ["errors with the install line when dam is not on PATH"] = function()
    local saved = vim.env.PATH
    vim.env.PATH = "/nonexistent-for-this-spec"
    require("damnit.dam").forget()

    local lines = report(health.check)

    vim.env.PATH = saved
    require("damnit.dam").forget()

    assert(said(lines, "error", "cargo install damnit"), vim.inspect(lines))
  end,

  ["warns for every remote whose credential comes from a command"] = function()
    local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/credential" })
    local lines = report(health.check)
    fake_dam.remove(fake)

    assert(said(lines, "warn", "needs a terminal"), vim.inspect(lines))
    assert(said(lines, "warn", "todoist"), "the warning names which remote")
  end,
}
```

`tests/fixtures/credential/remote.json` is `full/remote.json` with the remote's credential source
declared as a command:

```json
{"remotes": [{"remote": "todoist", "helper": "dam-remote-todoist", "url": "todoist::", "stale_seconds": 300, "credentials": [{"name": "token", "source": "command"}]}]}
```

Confirm the credential field's real name against `dam remote list --json` before writing the check; it is
the one field in this fixture that the design does not quote from dam's own output.

- [ ] **Step 2: Write the module**

The eight checks are: `dam` on `PATH`; `dam --version` against the supported range; the store and its
object count from `dam ls --json`; the config path; one line per remote; a warning per remote using a
`_command`; a warning with the count when `dam status --json` reports conflicts; and the declared view
names with an error naming any that `dam ls` refuses.

Each call runs inside `health.settle`, which is `vim.wait` keeping the loop turning so the
`vim.system` callbacks can run.

- [ ] **Step 3: Run, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua health_spec
nvim --headless --clean --cmd 'set rtp+=.' -c 'checkhealth damnit' -c 'qa!'
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: report dam, the store and the remotes in checkhealth"
```

---

### Task 27: The three CI greps and the performance spec

The architecture rules become a gate, and the performance targets become a warning a human reads.

**Files:**

- Modify: `.github/workflows/ci.yml`
- Create: `tests/performance_spec.lua`

- [ ] **Step 1: Add the greps to the lint job**

After the `luacheck` step in `.github/workflows/ci.yml`:

```yaml
      - name: Only the dam boundary spawns a process
        run: |
          if grep -rn 'vim\.system' lua --include='*.lua' | grep -v '^lua/damnit/dam\.lua:'; then
            echo "vim.system belongs in lua/damnit/dam.lua and nowhere else" >&2
            exit 1
          fi
      - name: Nothing waits on a dam call
        run: |
          if grep -rn ':wait(' lua --include='*.lua' | grep -v '^lua/damnit/health\.lua:'; then
            echo ":wait( belongs in lua/damnit/health.lua and in tests, and nowhere else" >&2
            exit 1
          fi
      - name: The pure modules call no Neovim API
        run: |
          pure="lua/damnit/status_model.lua lua/damnit/task_format.lua lua/damnit/list_format.lua"
          pure="$pure lua/damnit/tree.lua lua/damnit/location.lua lua/damnit/answer.lua"
          if grep -nE 'vim\.(api|fn|system|notify|schedule)' $pure; then
            echo "these six modules are pure: they may use vim.tbl_*, vim.json, vim.split and vim.deep_equal" >&2
            exit 1
          fi
```

- [ ] **Step 2: Prove each gate catches its own violation**

```bash
printf 'vim.system({ "dam" })\n' >> lua/damnit/render.lua
grep -rn 'vim\.system' lua --include='*.lua' | grep -v '^lua/damnit/dam\.lua:'
git checkout lua/damnit/render.lua
```

Expected: the grep prints the planted line, which is the gate firing. Repeat for the other two, and put
each file back.

- [ ] **Step 3: Write the performance spec**

Create `tests/performance_spec.lua`. It generates 2,000 objects, times each phase with `vim.uv.hrtime`
around it, takes the median of eleven runs, and **warns** rather than failing: a timing assertion
against a real spawn on a shared runner reddens main on untouched code.

```lua
---@param name string
---@param target_ms number
---@param run fun()
local function phase(name, target_ms, run)
  local samples = {}

  for _ = 1, 11 do
    local began = vim.uv.hrtime()
    run()
    samples[#samples + 1] = (vim.uv.hrtime() - began) / 1e6
  end

  table.sort(samples)
  local median = samples[6]

  if median > target_ms then
    io.write(("WARN %s took %.1fms, over its %.0fms target\n"):format(name, median, target_ms))
  end
end
```

The four phases, against a generated 2,000-object status:

```lua
---@param count integer
---@return table
local function generated(count)
  local unstaged = {}

  for index = 1, count do
    local oid = ("%040x"):format(index)
    unstaged[index] = {
      oid = oid,
      op = "update",
      before = { oid = oid, kind = "task", subject = "task " .. index, path = "work/", labels = {}, task = { priority = 2 } },
      after = { oid = oid, kind = "task", subject = "task " .. index .. "!", path = "work/", labels = {}, task = { priority = 1 } },
    }
  end

  return { unstaged = unstaged, staged = {}, conflicts = {}, notices = {}, unpushed = {} }
end

local status = generated(2000)
local state = { store = "/tmp/perf/dam.db" }
local model = nil
local lines = nil
local buf = vim.api.nvim_create_buf(false, true)

return {
  ["every phase is inside its target, or says which one is not"] = function()
    phase("modelling the document", 20, function()
      model = status_model.build(status, nil)
    end)

    phase("rendering lines and marks", 30, function()
      lines = render.lines(model, state)
    end)

    phase("a re-render after a write", 100, function()
      render.draw(buf, render.lines(status_model.build(status, nil), state))
    end)

    phase("status() on a redraw", 0.05, function()
      require("damnit.poll").status()
    end)

    assert(#lines > 2000, "the generated status really did render")
  end,
}
```

The case always passes: the warning is the output, and a human acting on it is the point. A timing
assertion against a real spawn on a shared runner reddens main on code nobody touched.

- [ ] **Step 4: Run, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua performance_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "ci: gate the architecture rules and warn on a slow phase"
```

---

### Task 28: The README

The document the repository presents. It is rewritten whole rather than edited, because every section
about the Todoist API, the token and the filter language describes something that no longer exists.

**Files:**

- Rewrite: `README.md`

- [ ] **Step 1: Write it**

The section list, in order: what it is and what `dam` is; requirements (Neovim 0.12.5, `dam` in the
supported range, no token); install, with the lazy.nvim spec from section 2 of the design; the staging
window and its key table; non-blocking, and what that means here; the task buffer; lists and named
views, with dam's query grammar; the quick edits; sending an object to the agent; searching; capture
from code; the completed history; the sidebar; the statusline; due reminders; health; options; the Lua
API; tests; license.

Three things the README must say plainly, because they are regressions or reversals a reader will hit:

- Priority 1 is the most urgent, which is the reverse of Todoist's scale.
- `X` in the list and `u` in the history do not work, because dam has no verb that reopens a completed
  task.
- `X` in the status window works on an uncommitted create only.

And one it must say because it is the point: this plugin holds no credential, and there is no option
that names one.

- [ ] **Step 2: Check every command and option it names**

```bash
grep -oE ':Dam [a-z]*' README.md | sort -u
grep -oE 'opts\.[a-z_.]+' README.md | sort -u
```

Expected: every command appears in `SUBCOMMANDS` in `plugin/damnit.lua`, and every option appears in
`M.options` in `lua/damnit/init.lua`. A name in the README and nowhere else is a lie; fix the README.

- [ ] **Step 3: Run the whole suite, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua | tail -1
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "docs: rewrite the README for damnit.nvim"
```

Expected: the whole suite green, and the run under five seconds with every individual spec under a
second.

---

## The tasks that wait on dam

Each of these needs a change being built in `webdavis/damnit` right now. Do not start one until its
named flag or field exists in the `dam` on `PATH`, and confirm it with the command each task gives
before writing code. Version one of the plugin ships without them and says so, which is what Tasks 1 to
28 deliver.

### Task 29: Reopening a completed task

**Waits on dam PR A: `dam edit <oid> --undone`.** Confirm with `dam edit --help | grep -- --undone`.

Blocks `X` in the list buffer, `u` in the completed history, and editing `done` in the task buffer.

**Files:** `lua/damnit/quick_edit.lua`, `lua/damnit/task_format.lua`, `tests/quick_edit_spec.lua`,
`tests/task_format_spec.lua`, `README.md`

- [ ] **Step 1: Write the failing test**

```lua
  ["X reopens a completed task"] = function()
    -- Open the completed history, press X on the first row, and assert the
    -- argv is `edit <oid> --undone --json` and that the view is read again.
  end,
```

Write it out against the fake the way `keys_spec` does, and add a `task_format_spec` case asserting
that `done: false` in the header sends `--undone` and `done: true` sends `--done`.

- [ ] **Step 2: Replace the refusal with the call**

In `lua/damnit/quick_edit.lua`, `M.reopen` becomes the write, and the sentence it used to print goes:

```lua
--- Reopen the object under the cursor.
function M.reopen()
  local object = require("damnit.list").object_under_cursor()
  if not object then
    return
  end

  require("damnit.list").write({ "edit", object.oid, "--undone", "--json" }, "edit")
end
```

In `lua/damnit/task_format.lua`, add `done` to `M.TASK_KEYS` and to `FLAGS` as
`done = { "--done", "--undone" }`, which is the one field whose clear flag is a real flag rather than a
negation of the set flag. Its value is read as `true` or `false` rather than as text.

- [ ] **Step 3: Bind it, correct the README, run, lint and commit**

Bind `X` in the list and `u` in the history, and delete the two README paragraphs saying they do not
work.

```bash
nvim --headless --clean -l tests/run.lua quick_edit_spec
nvim --headless --clean -l tests/run.lua task_format_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: reopen a completed task with dam edit --undone"
```

---

### Task 30: Discarding any working change

**Waits on dam PR A: `dam restore <oid>...` and `dam restore -A`.** Confirm with
`dam restore --help`.

`X` in the status window currently ships for a `create` only. With `restore` it works on all three ops
and it becomes undoable, which also removes the last reason the session undo was missed.

**Files:** `lua/damnit/actions.lua`, `tests/diff_spec.lua`, `README.md`

- [ ] **Step 1: Write the failing test**

Replace the case that asserts the refusal on an update with one asserting the call:

```lua
  ["X restores an update to its committed state"] = function()
    status_window.with(function(fake)
      vim.api.nvim_feedkeys("gu", "x", false)
      local before = #fake_dam.argv_log(fake)

      status_window.answer_input("y", function()
        vim.api.nvim_feedkeys("X", "x", false)
      end)

      fake_dam.settle(function()
        return #fake_dam.argv_log(fake) > before
      end)

      assert(
        fake_dam.argv_log(fake)[before + 1] == "restore 78b8950b02735107aa608659dcf19f6f50adfeb1 --json",
        vim.inspect(fake_dam.argv_log(fake))
      )
    end)
  end,
```

- [ ] **Step 2: Rewrite `M.discard`**

A `create` still goes through `dam rm`, because `restore` refuses an object with no committed state and
`rm` is that op's exact inverse. An `update` or a `delete` goes through `dam restore`. The prompt names
which of the two is about to happen, because one is reversible and the other is not.

- [ ] **Step 3: Run, correct the README, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua diff_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: discard any working change with dam restore"
```

---

### Task 31: Completing a parent without a terminal

**Waits on dam PR A: `dam done <oid> --force --children up|keep|into:<name> --depends drop|keep`.**
Confirm with `dam done --help | grep -- --children`.

The plugin can reach one disposition today, which is keeping the children where they are. These flags
are what let it offer the other two, and they are what make a forced completion possible at all on a
machine with `done.interactive = true`.

**Files:** `lua/damnit/quick_edit.lua`, `tests/done_spec.lua`, `README.md`

- [ ] **Step 1: Write the failing test**

```lua
  ["offers every disposition dam takes as a flag"] = function()
    -- The fake exits 2 on the first done. The choice list holds four entries:
    -- keep them where they are, move them up one level, move them into a new
    -- group, and cancel. Choosing the second sends
    -- `done <oid> --force --children up --json`.
  end,
```

Write it out in full, stubbing `vim.ui.select` to pick the second entry and asserting the argv.

- [ ] **Step 2: Offer the choices**

`M.send_done` gains a disposition argument, the `vim.ui.select` list grows from two entries to four,
and the `into:<name>` entry asks for the name through `vim.ui.input` before sending. The
`interactive_refusal` path goes, because a flag now answers the question dam was asking.

- [ ] **Step 3: Run, correct the README, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua done_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: choose what happens to the children when completing a parent"
```

---

### Task 32: The machine-readable error

**dam PR B landed as dam 0.2.0 on 2026-09-20.** Confirm with
`dam done <a blocked oid> --json 2>&1 >/dev/null | jq .error.rule`, which answers `"blocked"`.

Most of this task arrived with it. Task 4 already reads the document off standard error and puts
`kind`, `rule`, `oids` and `message` in the error table, Task 19 already reads `rule` and `oids`
rather than dam's prose, and the supported range already sits at `>=0.2.0 <0.3.0`. What is left is
the one caller that still keys off a word in a sentence.

**Files:** `lua/damnit/actions.lua`, `tests/actions_spec.lua`

- [ ] **Step 1: Write the failing test**

```lua
  ["names the remote whose credential is missing, off dam's kind"] = function()
    -- The fake exits 1 with { "error": { "kind": "credential", "rule": null,
    -- "message": "no credential for todoist", "oids": [] } }. The plugin's
    -- sentence is chosen by `err.kind == "credential"` and by nothing in the
    -- message.
  end,
```

- [ ] **Step 2: Key the credential sentence off the kind**

`actions.sync` tests `err.kind == "credential"` rather than searching the message for the word.
Every other caller already reads a field.

- [ ] **Step 3: Grep for the last of the prose matching**

```bash
grep -rn "find(\"" lua --include='*.lua'
```

Every hit must be a search of something this plugin wrote or of a buffer line, never of an
`err.message`.

- [ ] **Step 4: Run, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua actions_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "refactor: act on dam's error kind rather than on its wording"
```

---

### Task 33: The field summary from dam

**dam PR B landed as dam 0.2.0 on 2026-09-20: `"fields": [...]` in a change document.** Confirm with
`dam status --json | jq '.unstaged[0].fields'`.

The window's field summary is a copy of dam's own logic today. This makes it a read of dam's answer.

**Files:** `lua/damnit/status_model.lua`, `tests/status_model_spec.lua`

- [ ] **Step 1: Write the failing test**

```lua
  ["prefers the fields dam named over its own comparison"] = function()
    local model = status_model.build({
      unstaged = { { oid = "78b8950b", op = "update", fields = { "subject" }, before = {}, after = {} } },
      staged = {},
      conflicts = {},
      notices = {},
      unpushed = {},
    }, nil)

    assert(vim.deep_equal(model.sections[1].entries[1].fields, { "subject" }))
  end,
```

- [ ] **Step 2: Read it, and keep the comparison as the fallback**

```lua
  local fields = change.fields
  if fields == nil and change.op == "update" then
    fields = M.changed_fields(change.before, change.after)
  end
```

`M.changed_fields` and its golden case per field stay, because they are what keeps the fallback honest
against a dam that has not been updated.

- [ ] **Step 3: Run, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua status_model_spec
nvim --headless --clean -l tests/run.lua render_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "refactor: read a change's field list from dam"
```

---

### Task 34: Conflicts without their embedded objects

**dam PR B landed as dam 0.2.0 on 2026-09-20: `dam status --json` no longer carries the two objects
inside each conflict unless `--full` is passed.**
Confirm with `dam status --json | jq '.conflicts[0] | keys'`.

This one is a removal rather than an addition, so it breaks `<CR>` on a conflict, which reads
`conflicts[].ours` and `conflicts[].theirs` today. Do it the day dam's own change lands, not before.

**Files:** `lua/damnit/status_model.lua`, `lua/damnit/actions.lua`, `tests/open_spec.lua`,
`tests/fixtures/full/status.json`

- [ ] **Step 1: Trim the fixture and watch the tests fail**

Remove `ours` and `theirs` from the conflict in `tests/fixtures/full/status.json`.

Run: `nvim --headless --clean -l tests/run.lua open_spec`
Expected: the conflict case FAILs, because both sides render empty.

- [ ] **Step 2: Fetch the two sides**

`actions.open_conflict` queues two `dam show` calls, one per side, with whatever flag dam's change
gives for reading a conflict side. The two buffers open when both answer, so one half is never drawn
beside a blank.

`status_model.conflict_entry` keeps `ours` and `theirs` when they are present, so the plugin still works
against a dam that has not been updated. The conflict line's subject falls back to the oid when no
object came with the status.

- [ ] **Step 3: Run, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua open_spec
nvim --headless --clean -l tests/run.lua status_model_spec
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "refactor: read both sides of a conflict with dam show"
```

---

### Task 35: A read that promises to be local, and a header that says how fresh

**Waits on dam PR C: the global `--no-pull` flag, and `"last_pull"` in `dam remote list --json`.**
Confirm with `dam --no-pull ls --json` and `dam remote list --json | jq '.remotes[0].last_pull'`.

A remote with `stale` set makes `dam ls` pull before it answers, so the background poll cannot promise
to be local today. And the header can only count unpushed commits, never say how old the last pull is.

**Files:** `lua/damnit/poll.lua`, `lua/damnit/status_model.lua`, `lua/damnit/render.lua`,
`tests/poll_spec.lua`, `tests/render_spec.lua`, `tests/golden/*.txt`, `README.md`

- [ ] **Step 1: Write the failing tests**

The poll's fetch sends `--no-pull` before the subcommand, and the header reads
`todoist (1 unpushed, pulled 4m ago)`.

```lua
  ["the background poll never reaches the network"] = function()
    -- Start the poller, settle, and assert the argv is
    -- `--no-pull ls due:today | overdue --json`.
  end,
```

- [ ] **Step 2: Send the flag and read the timestamp**

`poll.refresh` prepends `--no-pull`. `status_model.build` carries `last_pull` onto each remote line, and
`render`'s `remotes_line` renders it as a relative age, computed in the renderer rather than in the
model so the model stays pure of a clock.

- [ ] **Step 3: Regenerate the goldens, read the diff, run, lint and commit**

```bash
DAMNIT_GOLDEN_UPDATE=1 nvim --headless --clean -l tests/run.lua render_spec
git diff tests/golden
nvim --headless --clean -l tests/run.lua | tail -1
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: keep the poll local and say how fresh each remote is"
```

The relative age must be computed from a clock the spec can fix, or the goldens will differ by a minute
depending on when they were generated. Pass the current time into `render.lines` through `state`, the
way the store and the running operation are passed.

---

### Task 36: dam's saved filters, listed rather than probed

**Waits on dam PR D: a command that lists dam's saved filters, and the category catalogue.** Confirm
with `dam filter list --json` or whatever spelling dam's change ships, read from `dam --help`.

Today an undeclared view name is handed to dam as a bare word and dam's refusal is what teaches the
plugin the name is in neither source. A listing means a name in neither is refused before any call, and
it means completion offers dam's names beside the declared ones.

**Files:** `lua/damnit/views.lua`, `plugin/damnit.lua`, `lua/damnit/health.lua`, `tests/views_spec.lua`

- [ ] **Step 1: Write the failing test**

```lua
  ["reads dam's filters once per session and offers them for completion"] = function()
    -- With a filter list holding `work`, `views.resolve("work")` answers a spec
    -- that is not a probe, and `views.declared()` holds both sources with the
    -- option's name winning a collision.
  end,
```

- [ ] **Step 2: Read the list once per session**

`views.load(callback)` runs the listing once and caches it. `views.resolve` consults `opts.views`, then
the cache, then refuses. `views.forget_filter` and the `probing` field go, and with them the case that
pinned the probe.

`:Dam list` and `:Dam pick` complete against both sources. `:checkhealth damnit` lists the names from
both and stops running one `dam ls` per declared name to find the refused ones, because the listing
answers that too.

- [ ] **Step 3: Run, correct the README, lint and commit**

```bash
nvim --headless --clean -l tests/run.lua views_spec
nvim --headless --clean -l tests/run.lua | tail -1
stylua --check . && luacheck .
git add -A
SKIP_AI_COMMIT=1 git commit -m "feat: list dam's saved filters instead of probing for one"
```
