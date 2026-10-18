local M = {}

local TESTS_DIR = arg[0]:match("(.*)/") or "."

local GLOBAL_FLAGS_TAKING_A_VALUE = { ["--store"] = true, ["--config"] = true }

local CANCELLED_LIKE_DAM = { code = 3, stdout = "", stderr = "dam: cancelled\n" }

local function has(argv, flag)
  return vim.tbl_contains(argv, flag)
end

local function subcommand_of(argv)
  local skip = false
  for index = 2, #argv do
    local arg = argv[index]
    if skip then
      skip = false
    elseif GLOBAL_FLAGS_TAKING_A_VALUE[arg] then
      skip = true
    elseif not vim.startswith(arg, "-") then
      return arg
    end
  end

  return ""
end

local function fixture_for(fake, argv, subcommand)
  local shape = has(argv, "--full") and "full" or has(argv, "!done") and "open" or nil
  local shaped = ("%s/%s-%s.json"):format(fake.fixtures, subcommand, shape)

  if shape and vim.uv.fs_stat(shaped) then
    return shaped
  end

  return ("%s/%s.json"):format(fake.fixtures, subcommand)
end

local function read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local text = file:read("a")
  file:close()

  return text
end

local function stderr_of(failure)
  return failure.stderr and failure.stderr .. "\n" or ""
end

local function answer_to(fake, argv)
  if has(argv, "--version") then
    return { code = 0, stdout = ("dam %s\n"):format(fake.version), stderr = "" }
  end

  local subcommand = subcommand_of(argv)
  local failure = fake.fail[subcommand] or fake
  local exit = tonumber(failure.exit) or 0

  if exit ~= 0 then
    return { code = exit, stdout = "", stderr = stderr_of(failure) }
  end

  local path = fixture_for(fake, argv, subcommand)
  local stdout = failure.stdout or read(path)
  if not stdout then
    return { code = 1, stdout = "", stderr = ("no fixture at %s\n"):format(path) }
  end

  return { code = 0, stdout = stdout, stderr = stderr_of(failure) }
end

local function deliver(fake, pending)
  fake.in_flight = fake.in_flight - 1
  fake.delivered = fake.delivered + 1
  pending.on_exit(pending.answer)
end

function M.install(opts)
  opts = opts or {}

  local fake = {
    fixtures = opts.fixtures or (TESTS_DIR .. "/fixtures/default"),
    version = opts.version or "0.2.0",
    exit = opts.exit,
    stderr = opts.stderr,
    stdout = opts.stdout,
    fail = opts.fail or {},
    hold = false,
    held = {},
    argv = {},
    in_flight = 0,
    delivered = 0,
  }

  function fake.run(argv, _, on_exit)
    table.insert(fake.argv, table.concat(argv, " ", 2))
    fake.in_flight = fake.in_flight + 1

    local pending = { answer = answer_to(fake, argv), on_exit = on_exit }
    local handle = {
      kill = function()
        pending.answer = CANCELLED_LIKE_DAM
      end,
    }

    if fake.hold then
      table.insert(fake.held, pending)
    else
      vim.schedule(function()
        deliver(fake, pending)
      end)
    end

    return handle
  end

  function fake.release()
    fake.hold = false
    local held = fake.held
    fake.held = {}

    for _, pending in ipairs(held) do
      vim.schedule(function()
        deliver(fake, pending)
      end)
    end
  end

  require("damnit").setup({}, { process = fake })

  return fake
end

function M.argv_log(fake)
  return fake.argv
end

local function installed()
  local fake = require("damnit").app().process
  assert(fake.in_flight, "no fake process is installed")

  return fake
end

local function turn_the_loop_once()
  vim.wait(1)
end

function M.settle(done)
  local fake = installed()

  while not done() do
    local delivered = fake.delivered
    turn_the_loop_once()

    assert(fake.in_flight > 0 or fake.delivered > delivered, "nothing is in flight and the condition does not hold")
    assert(#fake.held == 0, "answers are held; release them first")
  end
end

function M.drain()
  local fake = installed()
  fake.release()

  repeat
    local delivered = fake.delivered
    turn_the_loop_once()
  until fake.in_flight == 0 and fake.delivered == delivered
end

function M.remove(_)
  M.drain()
  require("damnit").setup({}, { process = require("damnit.process") })
end

return M
