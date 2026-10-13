local M = {}

local message = require("damnit.message")
local task_format = require("damnit.task_format")

M.NAMESPACE = vim.api.nvim_create_namespace("damnit.diagnostics")

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

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, task_format.render(object))
  vim.bo[buf].modified = false

  last_drawn_object_by_buf[buf] = object
  vim.diagnostic.reset(M.NAMESPACE, buf)

  return buf
end

local function run_in_order(buf, steps)
  local step = table.remove(steps, 1)

  require("damnit.queue").submit({
    args = step.args,
    label = step.label,
    on_done = function(updated, failure)
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      if failure then
        return diagnose(buf, failure.message, 1)
      end

      if #steps == 0 then
        return M.show(updated, buf)
      end

      run_in_order(buf, steps)
    end,
  })
end

function M.write(buf)
  local object = last_drawn_object_by_buf[buf]
  if not object then
    return message.warn("this buffer has no object to write")
  end

  vim.diagnostic.reset(M.NAMESPACE, buf)

  local header, body, err = task_format.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if err then
    return diagnose(buf, err, 1)
  end

  local changes, refused = task_format.changes(object, header, body)
  if refused then
    return diagnose(buf, refused.message, refused.line)
  end

  if #changes.edit == 0 and not changes.move then
    vim.bo[buf].modified = false

    return message.warn("nothing changed")
  end

  local steps = {}

  if #changes.edit > 0 then
    local args = { "edit", object.oid }
    vim.list_extend(args, changes.edit)
    args[#args + 1] = "--json"

    steps[#steps + 1] = { args = args, label = "edit" }
  end

  if changes.move then
    steps[#steps + 1] = { args = { "mv", object.oid, changes.move, "--json" }, label = "mv" }
  end

  run_in_order(buf, steps)
end

function M.open(oid)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(buf, ("damnit://task/%s"):format(oid))
  vim.bo[buf].filetype = "damtask"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false

  require("damnit.sidebar").leave_fixed_window()
  vim.api.nvim_win_set_buf(0, buf)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    desc = "dam: write this object back",
    callback = function()
      M.write(buf)
    end,
  })

  require("damnit.queue").submit({
    args = { "show", oid, "--json" },
    label = "show",
    on_done = function(object, err)
      if err then
        return message.report(err)
      end

      if vim.api.nvim_buf_is_valid(buf) then
        M.show(object, buf)
      end
    end,
  })

  return buf
end

return M
