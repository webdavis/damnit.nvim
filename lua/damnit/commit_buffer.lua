local M = {}
local dam_object = require("damnit.object")

local scratch = require("damnit.scratch")
local verbs = require("damnit.dam.verbs")
local window = require("damnit.window")
local write = require("damnit.write")

function M.message(lines)
  local non_comment_lines = {}

  for _, line in ipairs(lines) do
    if not vim.startswith(line, "#") then
      non_comment_lines[#non_comment_lines + 1] = line
    end
  end

  return vim.trim(table.concat(non_comment_lines, "\n"))
end

function M.write(app, buf)
  local text = M.message(vim.api.nvim_buf_get_lines(buf, 0, -1, false))

  if text == "" then
    return app.say.warn("no commit message; the commit was not made")
  end

  write.submit(app, {
    args = verbs.commit(text),
    label = "commit",
    on_ok = function(report)
      local count = #(report.changes or {})
      app.say.info(
        ("%s committed, %d %s"):format(dam_object.short_oid(report.id), count, count == 1 and "change" or "changes")
      )

      vim.bo[buf].modified = false
      vim.api.nvim_buf_delete(buf, { force = true })
      window.refresh(app)
    end,
  })
end

local function staged(app, key)
  local model = window.model(app, key)

  for _, section in ipairs((model or {}).sections or {}) do
    if section.kind == "staged" then
      return section
    end
  end

  return nil
end

local function configure(app, buf)
  vim.bo[buf].filetype = "damcommitmsg"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    desc = "dam: commit what this buffer says",
    callback = function()
      M.write(app, buf)
    end,
  })
end

function M.open(app, key)
  local section = staged(app, key)

  if not section then
    app.say.warn("nothing is staged to commit")

    return nil
  end

  local buf, created = scratch.named(("damnit://commit/%s"):format(key or app.store), function(new)
    configure(app, new)
  end)

  if scratch.focus(buf) then
    return buf
  end

  if created then
    local lines = { "", "# Staged" }
    for _, entry in ipairs(section.entries) do
      lines[#lines + 1] = ("# %-8s %s  %s"):format(entry.verb, dam_object.short_oid(entry.oid), entry.subject)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("startinsert")

  return buf
end

return M
