local M = {}

local fixed_window = require("damnit.fixed_window")
local scratch = require("damnit.scratch")
local task_edit = require("damnit.task_edit")
local task_header = require("damnit.task_header")
local verbs = require("damnit.dam.verbs")
local write = require("damnit.write")

M.NAMESPACE = vim.api.nvim_create_namespace("damnit.diagnostics")

vim.diagnostic.config({ virtual_text = true }, M.NAMESPACE)

local last_drawn_object_by_buf = {}

local function diagnose(buf, text, line)
  vim.diagnostic.set(M.NAMESPACE, buf, {
    {
      lnum = math.max(line - 1, 0),
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      source = "damnit",
      message = text,
    },
  })
end

function M.show(object, buf)
  buf = buf or vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, task_header.render(object))
  vim.bo[buf].modified = false

  last_drawn_object_by_buf[buf] = object
  vim.diagnostic.reset(M.NAMESPACE, buf)

  return buf
end

local function line_named_by(refusal, header)
  local flag = refusal:match("^(%-%-?[%w%-]+):")

  for key, flags in pairs(task_edit.FLAGS) do
    if flag == flags.set or flag == flags.clear then
      return (header[key] or {}).line or 1
    end
  end

  return 1
end

local function show_when_a_window_shows(object, buf)
  vim.bo[buf].modified = false

  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    once = true,
    callback = function()
      M.show(object, buf)
    end,
  })
end

local function run_in_order(app, buf, steps, header)
  local step = table.remove(steps, 1)

  app.queue.submit({
    args = step.args,
    label = step.label,
    on_done = function(updated, failure)
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      if failure then
        return diagnose(buf, failure.message, line_named_by(failure.message, header))
      end

      if #steps == 0 and #vim.fn.win_findbuf(buf) == 0 then
        return show_when_a_window_shows(updated, buf)
      end

      if #steps == 0 then
        return M.show(updated, buf)
      end

      run_in_order(app, buf, steps, header)
    end,
  })
end

function M.write(app, buf)
  local object = last_drawn_object_by_buf[buf]
  if not object then
    return app.say.warn("this buffer has no object to write")
  end

  vim.diagnostic.reset(M.NAMESPACE, buf)

  local header, body, err = task_header.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if err then
    return diagnose(buf, err, 1)
  end

  local changes, refused = task_edit.changes(object, header, body)
  if refused then
    return diagnose(buf, refused.message, refused.line)
  end

  if #changes.edit == 0 and not changes.move then
    vim.bo[buf].modified = false

    return app.say.warn("nothing changed")
  end

  local steps = {}

  if #changes.edit > 0 then
    steps[#steps + 1] = { args = verbs.edit(object.oid, changes.edit), label = "edit" }
  end

  if changes.move then
    steps[#steps + 1] = { args = verbs.mv(object.oid, changes.move), label = "mv" }
  end

  run_in_order(app, buf, steps, header)
end

local function configure(app, buf)
  vim.bo[buf].filetype = "damtask"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    desc = "dam: write this object back",
    callback = function()
      M.write(app, buf)
    end,
  })
end

function M.open(app, oid)
  local buf, created = scratch.named(("damnit://task/%s"):format(oid), function(new)
    configure(app, new)
  end)

  if not scratch.focus(buf) then
    fixed_window.leave()
    vim.api.nvim_win_set_buf(0, buf)
    vim.wo[0][0].signcolumn = "yes:1"
  end

  if not created then
    return buf
  end

  write.submit(app, {
    args = verbs.show(oid),
    label = "show",
    on_ok = function(object)
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      if #vim.fn.win_findbuf(buf) == 0 then
        return vim.api.nvim_buf_delete(buf, { force = true })
      end

      M.show(object, buf)
    end,
  })

  return buf
end

return M
