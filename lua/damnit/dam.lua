local M = {}

local answer = require("damnit.answer")
local one_read = require("damnit.one_read")
local timeout_seconds = require("damnit.process").timeout_seconds
local verbs = require("damnit.dam.verbs")

M.MIN_VERSION = "0.2.0"
M.MAX_VERSION = "0.3.0"

local function parts_of(text)
  local major, minor, patch = tostring(text):match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function compare(left, right)
  for index = 1, 3 do
    if left[index] ~= right[index] then
      return left[index] < right[index] and -1 or 1
    end
  end

  return 0
end

function M.supported(text)
  local parts = parts_of(text)
  if not parts then
    return false
  end

  return compare(parts, parts_of(M.MIN_VERSION)) >= 0 and compare(parts, parts_of(M.MAX_VERSION)) < 0
end

---@return damnit.Failure
local function refusal_for(version)
  if not version then
    return { kind = "missing", code = -1, plugin = true, message = answer.MISSING }
  end

  return {
    kind = "unsupported",
    code = 0,
    plugin = true,
    message = ("dam %s is outside the supported range >=%s <%s; update damnit.nvim"):format(
      version,
      M.MIN_VERSION,
      M.MAX_VERSION
    ),
  }
end

---@type damnit.Failure
local CANCELLED_BY_SETUP = {
  kind = "cancelled",
  code = -1,
  plugin = true,
  message = "the dam call was dropped when the options changed",
}

function M.new(options, process, say)
  local client = { version = nil }

  local handshake = { state = "unknown", refusal = nil, read = one_read.new() }
  local closed = false

  function client.argv(args)
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

  local function spawn(args, seconds, on_exit)
    return process.run(client.argv(args), seconds, on_exit)
  end

  local function read_the_banner(out)
    local banner = vim.trim(tostring(out.stdout or ""))
    local version = banner:match("dam%s+(%d+%.%d+%.%d+)")

    if out.missing or (out.code ~= 0 and not version) then
      handshake.state, handshake.refusal = "refused", refusal_for(nil)
    elseif not version then
      handshake.state = "ok"
      say.warn(("dam --version printed %q, which is not a version; going on anyway"):format(banner))
    elseif not M.supported(version) then
      handshake.state, handshake.refusal = "refused", refusal_for(version)
    else
      handshake.state, client.version = "ok", version
    end

    handshake.read.settle(handshake.refusal)
  end

  local function shake_hands(callback)
    if closed then
      return callback(CANCELLED_BY_SETUP)
    end

    if handshake.state == "ok" then
      return callback(nil)
    end

    if handshake.state == "refused" then
      return callback(handshake.refusal)
    end

    handshake.read.wait(callback, function()
      spawn(verbs.version(), timeout_seconds(options), function(out)
        if not closed then
          read_the_banner(out)
        end
      end)
    end)
  end

  ---@param callback fun(data: table?, err: damnit.Failure?)
  function client.call(args, opts, callback)
    opts = opts or {}

    shake_hands(function(err)
      if err then
        return callback(nil, err)
      end

      local seconds = timeout_seconds(options)

      local handle = spawn(args, seconds, function(out)
        callback(answer.interpret(out, opts.label, seconds))
      end)

      if opts.on_spawn then
        opts.on_spawn(handle)
      end
    end)
  end

  function client.close()
    closed = true
    handshake.read.settle(CANCELLED_BY_SETUP)
  end

  return client
end

return M
