local M = {}

local actions = require("damnit.actions")
local verbs = require("damnit.dam.verbs")
local window = require("damnit.window")

function M.remote_under_cursor(app)
  local found = window.entry_under_cursor(app)

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
  return ("if its source is a command that prompts, run dam %s in a terminal, and otherwise fix the source in dam's config"):format(
    verb
  )
end

local function one_line(verb, report)
  local lines = verb == "push" and push_lines(report) or pull_lines(report)

  if #lines == 0 then
    return "nothing to " .. verb
  end

  return table.concat(lines, "; ")
end

function M.sync(app, verb, remote)
  app.queue.submit({
    args = verbs[verb](remote),
    label = remote and ("%s %s"):format(verb, remote) or verb,
    verb = verb,
    network = true,
    on_done = function(report, err)
      if err and err.kind == "credential" then
        app.say.report({ kind = err.kind, message = err.message .. "; " .. credential_advice(verb) })
      elseif err then
        app.say.report(err)
      else
        app.say.info(one_line(verb, report))
      end

      window.forget_remotes(app)
      window.refresh(app)
    end,
  })
end

function M.push(app)
  local model = window.model(app)
  local any_remote_behind = false

  for _, remote in ipairs((model or {}).remotes or {}) do
    any_remote_behind = any_remote_behind or remote.commits > 0
  end

  if not any_remote_behind then
    return app.say.info("nothing to push")
  end

  M.sync(app, "push", M.remote_under_cursor(app))
end

function M.pull(app)
  M.sync(app, "pull", M.remote_under_cursor(app))
end

function M.resolve(app, side)
  local found = window.entry_under_cursor(app)

  if not found or found.entry.kind ~= "conflict" then
    return app.say.warn("no conflict on this line")
  end

  actions.write(app, verbs.resolve(found.entry.oid, side), "resolve")
end

return M
