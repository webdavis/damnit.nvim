local M = {}

local commit_buffer = require("damnit.commit_buffer")
local open = require("damnit.open")
local scratch = require("damnit.scratch")
local status_selection = require("damnit.status_selection")
local task_buffer = require("damnit.task_buffer")
local verbs = require("damnit.dam.verbs")
local window = require("damnit.window")
local write = require("damnit.write")

function M.refresh(app)
  window.forget_remotes(app)
  window.refresh(app)
end

function M.cancel(app)
  app.queue.cancel()
end

local function is_the_only_window_left()
  return #vim.api.nvim_list_tabpages() == 1 and #vim.api.nvim_tabpage_list_wins(0) == 1
end

function M.close(app)
  if is_the_only_window_left() then
    return app.say.warn("the status window is the only window open")
  end

  vim.api.nvim_win_close(0, false)
end

function M.jump_to_section(app, kind, heading)
  local line = window.line_of(app, kind, vim.v.count1)

  if not line then
    return app.say.warn(("no %s section"):format(heading))
  end

  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

function M.targets()
  local first = vim.api.nvim_win_get_cursor(0)[1]
  local last = first

  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    first, last = vim.fn.line("v"), vim.fn.line(".")

    if first > last then
      first, last = last, first
    end
  end

  return status_selection.targets(scratch.rows(vim.api.nvim_get_current_buf()), first, last)
end

function M.write(app, args, label)
  write.submit(app, { args = args, label = label, refresh = window.refresh })
end

function M.stage(app)
  local picked = M.targets()

  if #picked.oids == 0 then
    return app.say.warn("nothing to stage on this line")
  end

  if picked.section == "staged" then
    return app.say.warn("already staged")
  end

  M.write(app, verbs.add(picked.oids), "add")
end

function M.unstage(app)
  local picked = M.targets()

  if #picked.oids == 0 then
    return app.say.warn("nothing to stage on this line")
  end

  if picked.section ~= "staged" then
    return app.say.warn("not staged")
  end

  M.write(app, verbs.reset(picked.oids), "reset")
end

function M.toggle_stage(app)
  local picked = M.targets()

  if #picked.oids == 0 then
    return app.say.warn("nothing to stage on this line")
  end

  local verb = picked.section == "staged" and "reset" or "add"
  M.write(app, verbs[verb](picked.oids), verb)
end

function M.unstage_all(app)
  local model = window.model(app)
  local anything_staged = false

  for _, section in ipairs((model or {}).sections or {}) do
    anything_staged = anything_staged or section.kind == "staged"
  end

  if not anything_staged then
    return app.say.warn("nothing is staged")
  end

  M.write(app, verbs.reset(), "reset")
end

function M.discard(app)
  local found = window.entry_under_cursor(app)

  if not found or found.entry.kind ~= "change" then
    return app.say.warn("nothing to discard on this line")
  end

  local entry = found.entry
  local never_committed = entry.op == "create"
  local prompt = never_committed and 'Discard "%s"? It was never committed, so this removes it for good. (y/N) '
    or 'Discard "%s"? This puts it back to its last commit. (y/N) '

  vim.ui.input({ prompt = prompt:format(entry.subject) }, function(answer)
    if answer ~= "y" and answer ~= "Y" then
      return
    end

    if never_committed then
      return M.write(app, verbs.rm(entry.oid), "rm")
    end

    M.write(app, verbs.restore(entry.oid), "restore")
  end)
end

function M.toggle_diff(app)
  local found = window.entry_under_cursor(app)

  if not found or found.entry.kind ~= "change" then
    return app.say.warn("nothing to show on this line")
  end

  local entry = found.entry
  local open_diffs = window.open_diffs(app)
  open_diffs[entry.oid] = not open_diffs[entry.oid] or nil

  local drawn_status_has_no_objects_to_compare = not (entry.before or entry.after)
  if open_diffs[entry.oid] and drawn_status_has_no_objects_to_compare then
    return window.refresh(app)
  end

  window.redraw_current(app)
end

function M.open_under_cursor(app)
  local found = window.entry_under_cursor(app)

  if not found then
    return
  end

  local entry = found.entry

  if entry.kind == "conflict" then
    return open.conflict(app, entry)
  end

  if entry.kind == "remote" then
    return open.unpushed(app, entry)
  end

  if entry.kind ~= "change" then
    return
  end

  local window_dam_was_opened_from = window.origin()

  if window_dam_was_opened_from then
    vim.api.nvim_set_current_win(window_dam_was_opened_from)
  else
    vim.cmd("split")
  end

  task_buffer.open(app, entry.oid)
end

function M.commit(app)
  commit_buffer.open(app)
end

return M
