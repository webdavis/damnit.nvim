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

---@param module string
---@param fn string the name of a function on that module
---@param ... any the arguments it is called with
---@return fun()
local function call(module, fn, ...)
  local args = { ... }

  return function()
    require(module)[fn](unpack(args))
  end
end

---@param fn string the name of a function on damnit.actions
---@return fun()
local function act(fn)
  return call("damnit.actions", fn)
end

---@param fn string the name of a function on damnit.quick_edit
---@return fun()
local function edit(fn)
  return call("damnit.quick_edit", fn)
end

---@type table<string, { [1]: string|string[], [2]: string, [3]: fun(), [4]: string }[]>
M.MAPS = {
  damstatus = {
    { "n", "R", act("refresh"), "re-read the status" },
    { "n", "gu", jump("working", "Working"), "jump to Working" },
    { "n", "gs", jump("staged", "Staged"), "jump to Staged" },
    { "n", "gp", jump("unpushed", "Unpushed"), "jump to Unpushed" },
    { "n", "gn", jump("notices", "Notices"), "jump to Notices" },
    { "n", "gc", jump("conflicts", "Conflicts"), "jump to Conflicts" },
    { { "n", "x" }, "-", act("toggle_stage"), "stage or unstage this object" },
    { { "n", "x" }, "s", act("stage"), "stage this object" },
    { { "n", "x" }, "u", act("unstage"), "unstage this object" },
    { "n", "U", act("unstage_all"), "unstage everything" },
    { "n", "<CR>", act("open_under_cursor"), "open what the cursor is on" },
    { "n", "cc", act("commit"), "commit what is staged" },
    { "n", "X", act("discard"), "discard this working change" },
    { "n", "=", act("toggle_diff"), "show or hide this change's fields" },
    { "n", "P", call("damnit.sync", "push"), "push" },
    { "n", "p", call("damnit.sync", "pull"), "pull" },
    { "n", "co", call("damnit.sync", "resolve", "ours"), "resolve this conflict with ours" },
    { "n", "ct", call("damnit.sync", "resolve", "theirs"), "resolve this conflict with theirs" },
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
  damlist = {
    { "n", "<CR>", call("damnit.list", "open_under_cursor"), "open this object" },
    { "n", "R", call("damnit.list", "refresh"), "re-read this view" },
    { "n", "za", call("damnit.list", "toggle_fold"), "fold or unfold what is nested here" },
    { "n", "gd", call("damnit.list", "jump_to_location_under_cursor"), "jump to the code this came from" },
    { "n", "x", call("damnit.done", "complete"), "complete this object" },
    { "n", "X", edit("reopen"), "reopen this object" },
    { "n", "dd", edit("delete"), "remove this object, after the confirm" },
    { "n", "p", edit("cycle_priority"), "cycle this object's priority" },
    { "n", "s", edit("schedule"), "set this object's due date" },
    { "n", "l", edit("labels"), "toggle a label on this object" },
    { "n", "m", edit("move"), "move this object into another path" },
    { "n", "a", edit("add"), "add an object where the cursor is" },
    { "n", ">", edit("indent"), "move this object under the one above" },
    { "n", "<", edit("promote"), "move this object out from under its parent" },
    {
      "n",
      "g?",
      function()
        require("damnit.actions").help("damlist")
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
