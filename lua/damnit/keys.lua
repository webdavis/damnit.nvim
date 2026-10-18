local M = {}

local function jump(name, heading)
  return function()
    require("damnit.actions").jump_to_section(name, heading, vim.v.count1)
  end
end

local function call(module, function_name, ...)
  local args = { ... }

  return function()
    require(module)[function_name](unpack(args))
  end
end

local function act(function_name)
  return call("damnit.actions", function_name)
end

local function edit(function_name)
  return call("damnit.quick_edit", function_name)
end

M.MAPS = {
  damstatus = {
    { mode = "n", lhs = "R", run = act("refresh"), desc = "re-read the status" },
    { mode = "n", lhs = "gu", run = jump("working", "Working"), desc = "jump to Working" },
    { mode = "n", lhs = "gs", run = jump("staged", "Staged"), desc = "jump to Staged" },
    { mode = "n", lhs = "gp", run = jump("unpushed", "Unpushed"), desc = "jump to Unpushed" },
    { mode = "n", lhs = "gn", run = jump("notices", "Notices"), desc = "jump to Notices" },
    { mode = "n", lhs = "gc", run = jump("conflicts", "Conflicts"), desc = "jump to Conflicts" },
    { mode = { "n", "x" }, lhs = "-", run = act("toggle_stage"), desc = "stage or unstage this object" },
    { mode = { "n", "x" }, lhs = "s", run = act("stage"), desc = "stage this object" },
    { mode = { "n", "x" }, lhs = "u", run = act("unstage"), desc = "unstage this object" },
    { mode = "n", lhs = "U", run = act("unstage_all"), desc = "unstage everything" },
    { mode = "n", lhs = "<CR>", run = act("open_under_cursor"), desc = "open what the cursor is on" },
    { mode = "n", lhs = "cc", run = act("commit"), desc = "commit what is staged" },
    { mode = "n", lhs = "X", run = act("discard"), desc = "discard this working change" },
    { mode = "n", lhs = "=", run = act("toggle_diff"), desc = "show or hide this change's fields" },
    { mode = "n", lhs = "P", run = call("damnit.sync", "push"), desc = "push" },
    { mode = "n", lhs = "p", run = call("damnit.sync", "pull"), desc = "pull" },
    { mode = "n", lhs = "co", run = call("damnit.sync", "resolve", "ours"), desc = "resolve this conflict with ours" },
    {
      mode = "n",
      lhs = "ct",
      run = call("damnit.sync", "resolve", "theirs"),
      desc = "resolve this conflict with theirs",
    },
    { mode = "n", lhs = "<C-c>", run = act("cancel"), desc = "cancel the running operation" },
    { mode = "n", lhs = "q", run = act("close"), desc = "close the window" },
    { mode = "n", lhs = "gq", run = act("close"), desc = "close the window" },
    {
      mode = "n",
      lhs = "g?",
      run = function()
        require("damnit.actions").help("damstatus")
      end,
      desc = "show this help",
    },
  },
  damlist = {
    { mode = "n", lhs = "<CR>", run = call("damnit.list", "open_under_cursor"), desc = "open this object" },
    { mode = "n", lhs = "R", run = call("damnit.list", "refresh"), desc = "re-read this view" },
    { mode = "n", lhs = "za", run = call("damnit.list", "toggle_fold"), desc = "fold or unfold what is nested here" },
    {
      mode = "n",
      lhs = "gd",
      run = call("damnit.list", "jump_to_location_under_cursor"),
      desc = "jump to the code this came from",
    },
    { mode = "n", lhs = "x", run = call("damnit.done", "complete"), desc = "complete this object" },
    { mode = "n", lhs = "X", run = edit("reopen"), desc = "reopen this object" },
    { mode = "n", lhs = "u", run = edit("reopen_here"), desc = "reopen this object, in the completed history" },
    { mode = "n", lhs = "dd", run = edit("delete"), desc = "remove this object, after the confirm" },
    { mode = "n", lhs = "p", run = edit("cycle_priority"), desc = "cycle this object's priority" },
    { mode = "n", lhs = "s", run = edit("schedule"), desc = "set this object's due date" },
    { mode = "n", lhs = "l", run = edit("labels"), desc = "toggle a label on this object" },
    { mode = "n", lhs = "m", run = edit("move"), desc = "move this object into another path" },
    { mode = "n", lhs = "a", run = edit("add"), desc = "add an object where the cursor is" },
    { mode = "n", lhs = "S", run = call("damnit.send", "send"), desc = "hand this object to the agent pane" },
    { mode = "n", lhs = ">", run = edit("indent"), desc = "move this object under the one above" },
    { mode = "n", lhs = "<", run = edit("promote"), desc = "move this object out from under its parent" },
    {
      mode = "n",
      lhs = "g?",
      run = function()
        require("damnit.actions").help("damlist")
      end,
      desc = "show this help",
    },
  },
}

function M.attach(buf, filetype)
  for _, map in ipairs(M.MAPS[filetype] or {}) do
    vim.keymap.set(map.mode, map.lhs, map.run, { buffer = buf, nowait = true, desc = "dam: " .. map.desc })
  end
end

return M
