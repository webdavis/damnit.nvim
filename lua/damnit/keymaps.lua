local M = {}

local function call(feature, name, ...)
  return { feature = feature, name = name, args = { ... } }
end

local function jump(kind, heading)
  return call("actions", "jump_to_section", kind, heading)
end

local function act(name)
  return call("actions", name)
end

local function edit(name)
  return call("quick_edit", name)
end

M.MAPS = {
  damstatus = {
    {
      mode = "n",
      lhs = "g?",
      run = call("help", "open", "damstatus"),
      desc = "show this help",
      legend = "help",
    },
    {
      mode = { "n", "x" },
      lhs = "-",
      run = act("toggle_stage"),
      desc = "stage or unstage this object",
      legend = "stage",
    },
    { mode = "n", lhs = "cc", run = act("commit"), desc = "commit what is staged", legend = "commit" },
    { mode = "n", lhs = "P", run = call("sync", "push"), desc = "push", legend = "push" },
    { mode = "n", lhs = "p", run = call("sync", "pull"), desc = "pull", legend = "pull" },
    { mode = "n", lhs = "R", run = act("refresh"), desc = "re-read the status", legend = "re-read" },
    { mode = "n", lhs = "gu", run = jump("working", "Working"), desc = "jump to Working" },
    { mode = "n", lhs = "gs", run = jump("staged", "Staged"), desc = "jump to Staged" },
    { mode = "n", lhs = "gp", run = jump("unpushed", "Unpushed"), desc = "jump to Unpushed" },
    { mode = "n", lhs = "gn", run = jump("notices", "Notices"), desc = "jump to Notices" },
    { mode = "n", lhs = "gc", run = jump("conflicts", "Conflicts"), desc = "jump to Conflicts" },
    { mode = { "n", "x" }, lhs = "s", run = act("stage"), desc = "stage this object" },
    { mode = { "n", "x" }, lhs = "u", run = act("unstage"), desc = "unstage this object" },
    { mode = "n", lhs = "U", run = act("unstage_all"), desc = "unstage everything" },
    { mode = "n", lhs = "<CR>", run = act("open_under_cursor"), desc = "open what the cursor is on" },
    { mode = "n", lhs = "X", run = act("discard"), desc = "discard this working change" },
    { mode = "n", lhs = "=", run = act("toggle_diff"), desc = "show or hide this change's fields" },
    { mode = "n", lhs = "co", run = call("sync", "resolve", "ours"), desc = "resolve this conflict with ours" },
    {
      mode = "n",
      lhs = "ct",
      run = call("sync", "resolve", "theirs"),
      desc = "resolve this conflict with theirs",
    },
    { mode = "n", lhs = "<C-c>", run = act("cancel"), desc = "cancel the running operation" },
    { mode = "n", lhs = "q", run = act("close"), desc = "close the window" },
    { mode = "n", lhs = "gq", run = act("close"), desc = "close the window" },
  },
  damlist = {
    {
      mode = "n",
      lhs = "g?",
      run = call("help", "open", "damlist"),
      desc = "show this help",
      legend = "help",
    },
    {
      mode = "n",
      lhs = "<CR>",
      run = call("list", "open_under_cursor"),
      desc = "open this object",
      legend = "open",
    },
    { mode = "n", lhs = "x", run = call("done", "complete"), desc = "complete this object", legend = "done" },
    { mode = "n", lhs = "p", run = edit("cycle_priority"), desc = "cycle this object's priority", legend = "priority" },
    { mode = "n", lhs = "s", run = edit("schedule"), desc = "set this object's due date", legend = "due" },
    { mode = "n", lhs = "a", run = edit("add"), desc = "add an object where the cursor is", legend = "add" },
    { mode = "n", lhs = "R", run = call("list", "refresh"), desc = "re-read this view" },
    { mode = "n", lhs = "za", run = call("list", "toggle_fold"), desc = "fold or unfold what is nested here" },
    {
      mode = "n",
      lhs = "gd",
      run = call("list", "jump_to_location_under_cursor"),
      desc = "jump to the code this came from",
    },
    { mode = "n", lhs = "X", run = edit("reopen"), desc = "reopen this object" },
    { mode = "n", lhs = "u", run = edit("reopen_here"), desc = "reopen this object, in the completed history" },
    { mode = "n", lhs = "dd", run = edit("delete"), desc = "remove this object, after the confirm" },
    { mode = "n", lhs = "l", run = edit("labels"), desc = "toggle a label on this object" },
    { mode = "n", lhs = "m", run = edit("move"), desc = "move this object into another path" },
    { mode = "n", lhs = "S", run = call("send", "send"), desc = "hand this object to the agent pane" },
    { mode = "n", lhs = ">", run = edit("indent"), desc = "move this object under the one above" },
    { mode = "n", lhs = "<", run = edit("promote"), desc = "move this object out from under its parent" },
  },
}

local LEGEND_GAP = "  "

function M.legend(filetype, width)
  local shown, used = {}, 0

  for _, map in ipairs(M.MAPS[filetype] or {}) do
    if map.legend then
      local entry = map.lhs .. " " .. map.legend
      local needed = vim.api.nvim_strwidth(entry) + (#shown > 0 and #LEGEND_GAP or 0)

      if width and used + needed > width then
        break
      end

      shown[#shown + 1] = entry
      used = used + needed
    end
  end

  return table.concat(shown, LEGEND_GAP)
end

return M
