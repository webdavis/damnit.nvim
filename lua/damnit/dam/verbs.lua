local M = {}

local function appended(argv, more)
  for _, word in ipairs(more) do
    argv[#argv + 1] = word
  end

  return argv
end

local function json(argv)
  argv[#argv + 1] = "--json"

  return argv
end

function M.version()
  return { "--version" }
end

function M.status(full)
  return json(full and { "status", "--full" } or { "status" })
end

function M.ls(query, no_pull)
  local argv = { "ls" }

  if query ~= nil then
    argv[#argv + 1] = query
  end

  if no_pull then
    argv[#argv + 1] = "--no-pull"
  end

  return json(argv)
end

function M.show(oid)
  return json({ "show", oid })
end

function M.log()
  return json({ "log" })
end

function M.remote_list()
  return json({ "remote", "list" })
end

function M.filter_list()
  return json({ "filter", "list" })
end

function M.category_list()
  return json({ "category", "list" })
end

function M.add(oids)
  return json(appended({ "add" }, oids))
end

function M.reset(oids)
  return json(appended({ "reset" }, oids or {}))
end

function M.rm(oid)
  return json({ "rm", oid })
end

function M.restore(oid)
  return json({ "restore", oid })
end

function M.commit(text)
  return json({ "commit", "-m", text })
end

function M.new(subject, path, body)
  local argv = { "new", subject, "--path", path }

  if body then
    appended(argv, { "--body", body })
  end

  return json(argv)
end

function M.done(oid, children)
  local argv = { "done", oid }

  if children then
    appended(argv, { "--force", "--children", children })
  end

  return json(argv)
end

function M.edit(oid, flags)
  return json(appended({ "edit", oid }, flags))
end

function M.reopen(oid)
  return M.edit(oid, { "--undone" })
end

function M.priority(oid, priority)
  return M.edit(oid, { "-p", tostring(priority) })
end

function M.due(oid, due)
  return M.edit(oid, { "--due", due })
end

function M.label(oid, name)
  return M.edit(oid, { "--label", name })
end

function M.unlabel(oid, name)
  return M.edit(oid, { "--unlabel", name })
end

function M.mv(oid, path)
  return json({ "mv", oid, path })
end

local function sync(verb, remote)
  local argv = { verb }

  if remote then
    argv[#argv + 1] = remote
  end

  return json(argv)
end

function M.push(remote)
  return sync("push", remote)
end

function M.pull(remote)
  return sync("pull", remote)
end

function M.resolve(oid, side)
  return json({ "resolve", oid, "--" .. side })
end

return M
