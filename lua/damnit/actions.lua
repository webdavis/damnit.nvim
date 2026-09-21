-- What each key does: read the cursor, queue the call, handle the result.

local M = {}

local message = require("damnit.message")

--- Re-read the status. Queued like anything else, so it waits behind a push.
function M.refresh()
  require("damnit.window").refresh()
end

function M.cancel()
  require("damnit.queue").cancel()
end

--- Closing the only window of the only tab page is what Vim refuses with E444,
--- so the refusal is this plugin's own sentence instead.
function M.close()
  if #vim.api.nvim_list_tabpages() == 1 and #vim.api.nvim_tabpage_list_wins(0) == 1 then
    return message.warn("the status window is the only window open")
  end

  vim.api.nvim_win_close(0, false)
end

--- Move to the count-th entry of a section, or say the section is not there.
---@param kind string
---@param heading string
---@param count integer
function M.jump_to_section(kind, heading, count)
  local line = require("damnit.window").line_of(kind, count)

  if not line then
    return message.warn(("no %s section"):format(heading))
  end

  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

--- The key table for one filetype, in a float that closes on any key.
---@param filetype string
function M.help(filetype)
  local rows = {}
  for _, map in ipairs(require("damnit.keys").MAPS[filetype] or {}) do
    rows[#rows + 1] = ("  %-8s %s"):format(map[2], map[4])
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  vim.bo[buf].modifiable = false

  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, #row)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - #rows) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width + 2,
    height = #rows,
    style = "minimal",
    border = "rounded",
  })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.api.nvim_win_close, win, true)
    end,
  })
end

--- The objects the cursor or the visual range covers.
---
--- A section heading contributes every change in its section, which is what
--- makes `-` on a heading one call rather than one per line. A conflict or a
--- notice line contributes nothing.
---@return { oids: string[], section: string? }
function M.targets()
  local buf = vim.api.nvim_get_current_buf()
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}
  local oids = vim.b[buf].damnit_oids or {}

  local first = vim.api.nvim_win_get_cursor(0)[1]
  local last = first

  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    first, last = vim.fn.line("v"), vim.fn.line(".")

    if first > last then
      first, last = last, first
    end
  end

  local picked, seen, section = {}, {}, nil

  ---@param index integer
  local function take(index)
    local oid = oids[index]

    if oid and kinds[index] == "change" and not seen[oid] then
      seen[oid] = true
      picked[#picked + 1] = oid
      section = section or sections[index]
    end
  end

  for lnum = first, last do
    if kinds[lnum] == "section" then
      section = section or sections[lnum]

      for index, owner in ipairs(sections) do
        if owner == sections[lnum] then
          take(index)
        end
      end
    else
      take(lnum)
    end
  end

  return { oids = picked, section = section }
end

---@param verb string
---@param oids string[]
---@return string[]
local function verb_args(verb, oids)
  local args = { verb }
  vim.list_extend(args, oids)
  args[#args + 1] = "--json"

  return args
end

--- Queue one write, report a failure, and re-read the status either way.
---
--- The window shows what dam holds, never what a refused write intended.
---@param args string[]
---@param label string
function M.write(args, label)
  require("damnit.queue").submit({
    args = args,
    label = label,
    on_done = function(_, err)
      if err then
        message.report(err)
      end

      require("damnit.window").refresh()
    end,
  })
end

function M.stage()
  local picked = M.targets()

  if #picked.oids == 0 then
    return message.warn("nothing to stage on this line")
  end

  if picked.section == "staged" then
    return message.warn("already staged")
  end

  M.write(verb_args("add", picked.oids), "add")
end

function M.unstage()
  local picked = M.targets()

  if #picked.oids == 0 then
    return message.warn("nothing to stage on this line")
  end

  if picked.section ~= "staged" then
    return message.warn("not staged")
  end

  M.write(verb_args("reset", picked.oids), "reset")
end

--- Stage what is not staged, unstage what is.
function M.toggle_stage()
  local picked = M.targets()

  if #picked.oids == 0 then
    return message.warn("nothing to stage on this line")
  end

  local verb = picked.section == "staged" and "reset" or "add"
  M.write(verb_args(verb, picked.oids), verb)
end

--- `dam reset` with no oids unstages everything.
function M.unstage_all()
  local model = require("damnit.window").model()
  local staged = false

  for _, section in ipairs((model or {}).sections or {}) do
    staged = staged or section.kind == "staged"
  end

  if not staged then
    return message.warn("nothing is staged")
  end

  M.write({ "reset", "--json" }, "reset")
end

--- Throw away one working change.
---
--- Only a `create` has an exact inverse in dam: the object was never committed,
--- so removing it from the working layer leaves nothing behind. There is no
--- undo for it either, which is why the confirm has no way to be turned off.
function M.discard()
  local found = require("damnit.window").entry_under_cursor()

  if not found or found.entry.kind ~= "change" then
    return message.warn("nothing to discard on this line")
  end

  local entry = found.entry

  if entry.op ~= "create" then
    return message.warn("dam has no verb that restores a committed object; commit the change or edit it back")
  end

  vim.ui.input({
    prompt = ('Discard "%s"? This removes the object. (y/N) '):format(entry.subject),
  }, function(answer)
    if answer ~= "y" and answer ~= "Y" then
      return
    end

    M.write({ "rm", entry.oid, "--json" }, "rm")
  end)
end

--- Open or close the inline field diff of the change under the cursor.
function M.toggle_diff()
  local window = require("damnit.window")
  local found = window.entry_under_cursor()

  if not found or found.entry.kind ~= "change" then
    return message.warn("nothing to show on this line")
  end

  local entry = found.entry
  local open = window.open_diffs()
  open[entry.oid] = not open[entry.oid] or nil

  -- The status this window drew carries no objects to compare, so the first
  -- open re-reads one that does.
  if open[entry.oid] and not (entry.before or entry.after) then
    return window.refresh()
  end

  window.redraw_current()
end

--- Open whatever the cursor is on.
---
--- A change opens in the window `:Dam` was opened from, or in a split when the
--- status window is the only one.
function M.open_under_cursor()
  local window = require("damnit.window")
  local found = window.entry_under_cursor()

  if not found then
    return
  end

  local entry = found.entry
  local open = require("damnit.open")

  if entry.kind == "conflict" then
    return open.conflict(entry)
  end

  if entry.kind == "remote" then
    return open.unpushed(entry)
  end

  if entry.kind ~= "change" then
    return
  end

  local origin = window.origin()

  if origin then
    vim.api.nvim_set_current_win(origin)
  else
    vim.cmd("split")
  end

  require("damnit.task_buffer").open(entry.oid)
end

--- Commit what is staged, through a message buffer.
function M.commit()
  require("damnit.commit_buffer").open()
end

return M
