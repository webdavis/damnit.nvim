local M = {}

local SCRIPT = [==[#!/bin/sh
answer_an_interrupt_with_exit_3_like_dam() {
  kill $sleeper 2>/dev/null
  exit 3
}

trap_interrupts_before_the_first_write_a_caller_may_wait_on() {
  trap answer_an_interrupt_with_exit_3_like_dam INT
  trap answer_an_interrupt_with_exit_3_like_dam TERM
}

record_argv() {
  printf '%s\n' "$*" >> "$DAMNIT_TEST_LOG"
}

asks_for_the_version_anywhere_among_the_global_flags() {
  case " $* " in
    *" --version "*) return 0 ;;
  esac
  return 1
}

find_the_subcommand_past_global_flags_and_their_values() {
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
}

sleep_in_the_background_so_a_trap_answers_at_once_and_no_pipe_is_held() {
  sleep "$DAMNIT_TEST_SLEEP" >/dev/null 2>&1 &
  sleeper=$!
  wait $sleeper
}

find_the_fixture_preferring_the_full_or_open_shape_when_asked_for() {
  fixture="$DAMNIT_TEST_FIXTURES/$subcommand.json"
  case " $* " in
    *" --full "*) shape="full" ;;
    *" !done "*) shape="open" ;;
    *) return ;;
  esac
  if [ -f "$DAMNIT_TEST_FIXTURES/$subcommand-$shape.json" ]; then
    fixture="$DAMNIT_TEST_FIXTURES/$subcommand-$shape.json"
  fi
}

trap_interrupts_before_the_first_write_a_caller_may_wait_on
record_argv "$@"

if asks_for_the_version_anywhere_among_the_global_flags "$@"; then
  echo "dam ${DAMNIT_TEST_VERSION:-0.2.0}"
  exit 0
fi

find_the_subcommand_past_global_flags_and_their_values "$@"

if [ -n "$DAMNIT_TEST_SLEEP" ]; then sleep_in_the_background_so_a_trap_answers_at_once_and_no_pipe_is_held; fi

fails_this_subcommand() {
  [ -z "$DAMNIT_TEST_FAIL_SUBCOMMAND" ] || [ "$DAMNIT_TEST_FAIL_SUBCOMMAND" = "$subcommand" ]
}

if fails_this_subcommand; then
  if [ -n "$DAMNIT_TEST_STDERR" ]; then printf '%s\n' "$DAMNIT_TEST_STDERR" >&2; fi
  if [ -n "$DAMNIT_TEST_EXIT" ] && [ "$DAMNIT_TEST_EXIT" != 0 ]; then exit "$DAMNIT_TEST_EXIT"; fi
fi

find_the_fixture_preferring_the_full_or_open_shape_when_asked_for "$@"
cat "$fixture"
]==]

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local HOME_VARIABLES_SANDBOXED_TO_THE_SCRIPT_DIR = { "HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME" }

local VARIABLES_THAT_DRIVE_THE_SCRIPT = {
  "DAMNIT_TEST_LOG",
  "DAMNIT_TEST_FIXTURES",
  "DAMNIT_TEST_VERSION",
  "DAMNIT_TEST_SLEEP",
  "DAMNIT_TEST_STDERR",
  "DAMNIT_TEST_EXIT",
  "DAMNIT_TEST_FAIL_SUBCOMMAND",
}

local function failure_in(opts)
  local subcommand, failure = next(opts.fail or {})
  assert(subcommand == nil or next(opts.fail, subcommand) == nil, "fail names one subcommand")

  return subcommand or "", failure or opts
end

function M.install(opts)
  opts = opts or {}

  local script_dir = vim.fn.tempname()
  vim.fn.mkdir(script_dir, "p")

  local script = script_dir .. "/dam"
  local file = assert(io.open(script, "w"))
  file:write(SCRIPT)
  file:close()
  assert(vim.uv.fs_chmod(script, tonumber("755", 8)))

  local fake = {
    script_dir = script_dir,
    argv_log_path = script_dir .. "/argv.log",
    path_before_install = vim.env.PATH,
    home_variables_before_install = {},
  }

  for _, name in ipairs(HOME_VARIABLES_SANDBOXED_TO_THE_SCRIPT_DIR) do
    fake.home_variables_before_install[name] = vim.env[name]
    vim.env[name] = script_dir
  end

  vim.env.PATH = script_dir .. ":" .. vim.env.PATH
  vim.env.DAMNIT_TEST_LOG = fake.argv_log_path
  vim.env.DAMNIT_TEST_FIXTURES = opts.fixtures or (TESTS_DIR .. "/fixtures/default")
  vim.env.DAMNIT_TEST_VERSION = opts.version or "0.2.0"
  vim.env.DAMNIT_TEST_SLEEP = opts.sleep or ""

  local fail_subcommand, failure = failure_in(opts)
  vim.env.DAMNIT_TEST_FAIL_SUBCOMMAND = fail_subcommand
  vim.env.DAMNIT_TEST_STDERR = failure.stderr or ""
  vim.env.DAMNIT_TEST_EXIT = failure.exit and tostring(failure.exit) or ""

  require("damnit").setup({}, { process = require("damnit.process") })

  return fake
end

function M.argv_log(fake)
  local lines = {}

  local file = io.open(fake.argv_log_path, "r")
  if not file then
    return lines
  end

  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()

  return lines
end

M.SETTLE_CAP_MS = 15000

function M.settle(done, ms)
  assert(vim.wait(ms or M.SETTLE_CAP_MS, done, 5), "the dam call never answered")
end

function M.remove(fake)
  vim.env.PATH = fake.path_before_install

  for _, name in ipairs(HOME_VARIABLES_SANDBOXED_TO_THE_SCRIPT_DIR) do
    vim.env[name] = fake.home_variables_before_install[name]
  end

  vim.fn.delete(fake.script_dir, "rf")

  for _, name in ipairs(VARIABLES_THAT_DRIVE_THE_SCRIPT) do
    vim.env[name] = nil
  end

  require("damnit").setup({}, { process = require("damnit.process") })
end

return M
