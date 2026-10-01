local M = {}

local entries = require("damnit.window.entries")
local folds = require("damnit.folds")
local layout = require("damnit.window.layout")
local message = require("damnit.message")
local queue = require("damnit.queue")
local render = require("damnit.render")
local status_model = require("damnit.status_model")

local buffer_by_store = {}

local model_by_store = {}

local remote_list_by_store = {}

local window_dam_was_opened_from = nil

function M.store_display(key)
  if key == "default" then
    return "dam's default"
  end

  return vim.fn.fnamemodify(key, ":~")
end

local function window_for(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end

  return nil
end

function M.buffer(key)
  key = key or queue.key()

  local existing = buffer_by_store[key]
  if existing and vim.api.nvim_buf_is_valid(existing) then
    return existing
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ("damnit://status/%s"):format(key))
  vim.bo[buf].filetype = "damstatus"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].modifiable = false

  require("damnit.keys").attach(buf, "damstatus")
  buffer_by_store[key] = buf

  return buf
end

function M.open()
  local key = queue.key()
  render.define()

  local buf = M.buffer(key)
  local win = window_for(buf)

  if win then
    vim.api.nvim_set_current_win(win)
  else
    window_dam_was_opened_from = vim.api.nvim_get_current_win()

    layout.open(buf, require("damnit").options.window.float)
  end

  M.refresh(key)

  return buf
end

function M.origin()
  if window_dam_was_opened_from and vim.api.nvim_win_is_valid(window_dam_was_opened_from) then
    return window_dam_was_opened_from
  end

  return nil
end

function M.model(key)
  return model_by_store[key or queue.key()]
end

function M.line_of(section_kind, nth)
  local buf = buffer_by_store[queue.key()]
  if not buf then
    return nil
  end

  return entries.line_of(buf, section_kind, nth)
end

function M.entry_under_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "damstatus" then
    return nil
  end

  return entries.at_line(buf, vim.api.nvim_win_get_cursor(0)[1], M.model())
end

local function draw(key, lines)
  local buf = buffer_by_store[key]
  local win = window_for(buf)
  local oid = nil
  local lnum = 1

  if win then
    lnum = vim.api.nvim_win_get_cursor(win)[1]
    oid = (vim.b[buf].damnit_oids or {})[lnum]
    folds.remember(key, win)
  end

  render.draw(buf, lines)
  require("damnit.render.diff").apply(buf, key, model_by_store[key])

  if not win then
    return
  end

  local target = lnum
  if oid then
    for index, each in ipairs(vim.b[buf].damnit_oids or {}) do
      if each == oid then
        target = index
        break
      end
    end
  end

  local count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(win, { math.min(math.max(target, 1), count), 0 })
  folds.apply(key, win)
end

function M.open_diffs(key)
  return require("damnit.render.diff").open_set(key or queue.key())
end

local function header_state(key)
  return { store = M.store_display(key), running = queue.foreground(key), now = os.time() }
end

function M.redraw_current(key)
  key = key or queue.key()

  if not model_by_store[key] then
    return
  end

  draw(key, render.lines(model_by_store[key], header_state(key)))
end

function M.redraw(key, status)
  local buf = buffer_by_store[key]
  if not buf or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  model_by_store[key] = status_model.build(status, remote_list_by_store[key])

  draw(key, render.lines(model_by_store[key], header_state(key)))
end

local function read_the_remote_list_until_cached(key)
  if remote_list_by_store[key] ~= nil then
    return
  end

  queue.submit({
    args = { "remote", "list", "--json" },
    label = "remote list",
    on_done = function(data)
      remote_list_by_store[key] = data
    end,
  })
end

local function status_args_full_while_a_diff_is_open(key)
  if next(require("damnit.render.diff").open_set(key)) ~= nil then
    return { "status", "--full", "--json" }
  end

  return { "status", "--json" }
end

function M.refresh(key)
  key = key or queue.key()

  read_the_remote_list_until_cached(key)

  queue.submit({
    args = status_args_full_while_a_diff_is_open(key),
    label = "status",
    on_done = function(status, err)
      if err then
        return message.report(err)
      end

      M.redraw(key, status)
    end,
  })
end

function M.forget_remotes(key)
  remote_list_by_store[key or queue.key()] = nil
end

function M.tick(key)
  local buf = buffer_by_store[key]
  if not buf or not vim.api.nvim_buf_is_loaded(buf) or not model_by_store[key] then
    return
  end

  local lines = render.lines(model_by_store[key], header_state(key))

  local header_count = 0
  for _, line in ipairs(lines) do
    if line.kind ~= "header" then
      break
    end
    header_count = header_count + 1
  end

  local drawn_header_count = 0
  for _, kind in ipairs(vim.b[buf].damnit_kinds or {}) do
    if kind ~= "header" then
      break
    end
    drawn_header_count = drawn_header_count + 1
  end

  if header_count ~= drawn_header_count then
    return draw(key, lines)
  end

  local head = {}
  local text = {}
  for index = 1, header_count do
    head[index] = lines[index]
    text[index] = lines[index].text
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, header_count, false, text)
  vim.bo[buf].modifiable = false

  render.mark(buf, head, 0)
end

queue.on_tick(M.tick)

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = vim.api.nvim_create_augroup("damnit", { clear = false }),
  pattern = "damnit://status/*",
  desc = "dam: :e re-reads the status",
  callback = function()
    M.refresh()
  end,
})

return M
