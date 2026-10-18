local verbs = require("damnit.dam.verbs")

local OID = "1111111111111111111111111111111111111111"

local function says(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect(actual))
end

return {
  ["asks for the version with no json flag"] = function()
    says(verbs.version(), { "--version" })
  end,

  ["reads the status, full only when asked"] = function()
    says(verbs.status(), { "status", "--json" })
    says(verbs.status(true), { "status", "--full", "--json" })
  end,

  ["lists by query, without pulling only when asked"] = function()
    says(verbs.ls("!done"), { "ls", "!done", "--json" })
    says(verbs.ls(nil, true), { "ls", "--no-pull", "--json" })
    says(verbs.ls("due:today", true), { "ls", "due:today", "--no-pull", "--json" })
  end,

  ["keeps an empty query as dam's own argument"] = function()
    says(verbs.ls("", true), { "ls", "", "--no-pull", "--json" })
  end,

  ["reads one object, the log and the lists dam keeps"] = function()
    says(verbs.show(OID), { "show", OID, "--json" })
    says(verbs.log(), { "log", "--json" })
    says(verbs.remote_list(), { "remote", "list", "--json" })
    says(verbs.filter_list(), { "filter", "list", "--json" })
    says(verbs.category_list(), { "category", "list", "--json" })
  end,

  ["stages and unstages every oid it is given"] = function()
    says(verbs.add({ OID, "2" }), { "add", OID, "2", "--json" })
    says(verbs.reset({ OID }), { "reset", OID, "--json" })
  end,

  ["unstages everything when reset names no oid"] = function()
    says(verbs.reset(), { "reset", "--json" })
  end,

  ["removes, restores and commits"] = function()
    says(verbs.rm(OID), { "rm", OID, "--json" })
    says(verbs.restore(OID), { "restore", OID, "--json" })
    says(verbs.commit("Ship it"), { "commit", "-m", "Ship it", "--json" })
  end,

  ["creates an object under a path, with a body only when given one"] = function()
    says(verbs.new("Call Ana", "inbox/"), { "new", "Call Ana", "--path", "inbox/", "--json" })
    says(
      verbs.new("Call Ana", "inbox/", "from notes.md:3"),
      { "new", "Call Ana", "--path", "inbox/", "--body", "from notes.md:3", "--json" }
    )
  end,

  ["completes an object, forcing only when it names where the children go"] = function()
    says(verbs.done(OID), { "done", OID, "--json" })
    says(verbs.done(OID, "into:later"), { "done", OID, "--force", "--children", "into:later", "--json" })
  end,

  ["edits an object with the flags it is given"] = function()
    says(verbs.edit(OID, { "--subject", "New", "--no-due" }), { "edit", OID, "--subject", "New", "--no-due", "--json" })
  end,

  ["spells the quick edits"] = function()
    says(verbs.reopen(OID), { "edit", OID, "--undone", "--json" })
    says(verbs.priority(OID, 2), { "edit", OID, "-p", "2", "--json" })
    says(verbs.due(OID, "tomorrow"), { "edit", OID, "--due", "tomorrow", "--json" })
    says(verbs.label(OID, "home"), { "edit", OID, "--label", "home", "--json" })
    says(verbs.unlabel(OID, "home"), { "edit", OID, "--unlabel", "home", "--json" })
  end,

  ["moves an object to a path"] = function()
    says(verbs.mv(OID, "work/"), { "mv", OID, "work/", "--json" })
  end,

  ["pushes and pulls one remote or every remote"] = function()
    says(verbs.push("origin"), { "push", "origin", "--json" })
    says(verbs.push(), { "push", "--json" })
    says(verbs.pull("origin"), { "pull", "origin", "--json" })
    says(verbs.pull(), { "pull", "--json" })
  end,

  ["resolves a conflict for one side"] = function()
    says(verbs.resolve(OID, "ours"), { "resolve", OID, "--ours", "--json" })
  end,
}
