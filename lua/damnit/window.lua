local M = {}

local diff = require("damnit.render.diff")
local entries = require("damnit.window.entries")
local header = require("damnit.window.header")
local highlights = require("damnit.render.highlights")
local layout = require("damnit.window.layout")
local remotes = require("damnit.window.remotes")
local status_draw = require("damnit.window.draw")
local status_lines = require("damnit.render.status_lines")
local status_model = require("damnit.status_model")
local verbs = require("damnit.dam.verbs")

local buffer_by_store = {}

local model_by_store = {}

local window_dam_was_opened_from = nil

local function window_for(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end

  return nil
end

function M.buffer(app, key)
  key = key or app.store

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

  buffer_by_store[key] = buf

  return buf
end

function M.open(app)
  local key = app.store
  highlights.define()

  local buf = M.buffer(app, key)
  local win = window_for(buf)

  if win then
    vim.api.nvim_set_current_win(win)
  else
    window_dam_was_opened_from = vim.api.nvim_get_current_win()

    layout.open(buf, app.options.window.float)
  end

  M.refresh(app, key)

  return buf
end

function M.origin()
  if window_dam_was_opened_from and vim.api.nvim_win_is_valid(window_dam_was_opened_from) then
    return window_dam_was_opened_from
  end

  return nil
end

function M.model(app, key)
  return model_by_store[key or app.store]
end

function M.line_of(app, section_kind, nth)
  local buf = buffer_by_store[app.store]
  if not buf then
    return nil
  end

  return entries.line_of(buf, section_kind, nth)
end

function M.entry_under_cursor(app)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "damstatus" then
    return nil
  end

  return entries.at_line(buf, vim.api.nvim_win_get_cursor(0)[1], M.model(app))
end

local function draw(key, lines)
  local buf = buffer_by_store[key]

  status_draw.draw(buf, window_for(buf), key, model_by_store[key], lines)
end

function M.open_diffs(app, key)
  return diff.open_set(key or app.store)
end

local function header_state(app, key)
  return header.state(app, key, window_for(buffer_by_store[key]))
end

function M.redraw_current(app, key)
  key = key or app.store

  if not model_by_store[key] then
    return
  end

  draw(key, status_lines.lines(model_by_store[key], header_state(app, key)))
end

function M.redraw(app, key, status)
  local buf = buffer_by_store[key]
  if not buf or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  model_by_store[key] = status_model.build(status, remotes.of(key))

  draw(key, status_lines.lines(model_by_store[key], header_state(app, key)))
end

local function status_args_full_while_a_diff_is_open(key)
  if next(diff.open_set(key)) ~= nil then
    return verbs.status(true)
  end

  return verbs.status()
end

function M.refresh(app, key)
  key = key or app.store

  remotes.read_until_cached(app, key)

  app.queue.submit({
    args = status_args_full_while_a_diff_is_open(key),
    label = "status",
    on_done = function(status, err)
      if err then
        return app.say.report(err)
      end

      M.redraw(app, key, status)
    end,
  })
end

function M.forget_remotes(app, key)
  remotes.forget(key or app.store)
end

function M.tick(app, key)
  local buf = buffer_by_store[key]
  if not buf or not vim.api.nvim_buf_is_loaded(buf) or not model_by_store[key] then
    return
  end

  header.rewrite(buf, status_lines.lines(model_by_store[key], header_state(app, key)))
end

function M.tick_every_store(app)
  for key in pairs(buffer_by_store) do
    M.tick(app, key)
  end
end

return M
