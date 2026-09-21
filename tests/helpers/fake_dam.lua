-- A fake `dam` at the front of PATH.
--
-- Four environment variables drive every case: which fixture directory to read,
-- how long to sleep, what to write on standard error, and what to exit with.
-- The argv log is what every assertion about "what the plugin sent" reads.

local M = {}

local SCRIPT = [==[#!/bin/sh
# dam exits 3 on an interrupt. The traps are installed before the first write,
# because a caller that waits for that write and then signals can beat a trap
# installed after it.
trap 'kill $sleeper 2>/dev/null; exit 3' INT
trap 'kill $sleeper 2>/dev/null; exit 3' TERM

# Records its argv, then replays the fixture named for its subcommand.
printf '%s\n' "$*" >> "$DAMNIT_TEST_LOG"

case "$1" in
  --version) echo "dam ${DAMNIT_TEST_VERSION:-0.1.0}"; exit 0 ;;
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

# The sleep runs in the background and the script waits on it, so the trap runs
# the moment the signal arrives. It owns neither of this script's pipes, so a
# caller reading them sees the exit as soon as the trap runs.
if [ -n "$DAMNIT_TEST_SLEEP" ]; then sleep "$DAMNIT_TEST_SLEEP" >/dev/null 2>&1 & sleeper=$!; wait $sleeper; fi

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
  vim.env.DAMNIT_TEST_VERSION = opts.version or "0.1.0"
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
