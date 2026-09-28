local M = {}

local message = require("damnit.message")

function M.remote_under_cursor()
  local found = require("damnit.window").entry_under_cursor()

  if found and found.entry.kind == "remote" then
    return found.entry.remote
  end

  return nil
end

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

local function credential_advice(verb)
  return ("dam could not resolve this remote's credential; if its source is a command that prompts, run dam %s in a terminal, and otherwise fix the source in dam's config"):format(
    verb
  )
end

function M.sync(verb, remote)
  local args = { verb }

  if remote then
    args[#args + 1] = remote
  end

  args[#args + 1] = "--json"

  require("damnit.queue").submit({
    args = args,
    label = remote and ("%s %s"):format(verb, remote) or verb,
    verb = verb,
    network = true,
    on_done = function(report, err)
      if err then
        message.report(err)

        if err.kind == "credential" then
          message.warn(credential_advice(verb))
        end
      else
        for _, line in ipairs(verb == "push" and push_lines(report) or pull_lines(report)) do
          message.say(line)
        end
      end

      local window = require("damnit.window")
      window.forget_remotes()
      window.refresh()
    end,
  })
end

function M.push()
  local model = require("damnit.window").model()
  local any_remote_behind = false

  for _, remote in ipairs((model or {}).remotes or {}) do
    any_remote_behind = any_remote_behind or remote.commits > 0
  end

  if not any_remote_behind then
    return message.warn("nothing to push")
  end

  M.sync("push", M.remote_under_cursor())
end

function M.pull()
  M.sync("pull", M.remote_under_cursor())
end

function M.resolve(side)
  local found = require("damnit.window").entry_under_cursor()

  if not found or found.entry.kind ~= "conflict" then
    return message.warn("no conflict on this line")
  end

  require("damnit.actions").write({ "resolve", found.entry.oid, "--" .. side, "--json" }, "resolve")
end

return M
