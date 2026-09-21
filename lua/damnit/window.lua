-- Creating, finding and focusing the status window and its buffer.
--
-- One buffer per store, keyed the way the queue is keyed. The buffer is redrawn
-- in full from a fresh `dam status --json`; nothing patches it in place, so what
-- is on screen came from dam rather than from a guess at what a write did.

local M = {}

local message = require("damnit.message")
local queue = require("damnit.queue")
local render = require("damnit.render")
local status_model = require("damnit.status_model")

---@type table<string, integer>
local buffers = {}

---@type table<string, damnit.Model>
local models = {}

---@type table<string, table>
local remotes = {}

---@type table<string, table<string, boolean>>
local folded = {}

---@type integer?
local origin = nil

--- The store as the header names it. dam does not report its own default path,
--- and this plugin does not hardcode one.
---@param key string
---@return string
local function store_display(key)
  if key == "default" then
    return "dam's default"
  end

  return vim.fn.fnamemodify(key, ":~")
end

--- The fold level of one line, read off the kinds the renderer recorded.
---@param lnum integer
---@return string
function M.fold_level(lnum)
  local kind = (vim.b.damnit_kinds or {})[lnum]

  if kind == "section" then
    return ">1"
  end

  if kind == "header" or kind == "blank" or kind == "empty" then
    return "0"
  end

  return "1"
end

---@param buf integer
---@return integer? win
local function window_for(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end

  return nil
end

---@param key string?
---@return integer buf
function M.buffer(key)
  key = key or queue.key()

  local existing = buffers[key]
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
  buffers[key] = buf

  return buf
end

---@param win integer
local function configure(win)
  vim.wo[win].foldmethod = "expr"
  vim.wo[win].foldexpr = "v:lua.require'damnit.window'.fold_level(v:lnum)"
  vim.wo[win].foldlevel = 99
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
end

---@param buf integer
local function open_split(buf)
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, math.max(math.floor(vim.o.lines / 3), 10))
end

---@param buf integer
local function open_float(buf)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.7)

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.win then
    snacks.win({ buf = buf, width = width, height = height, border = "rounded" })

    return
  end

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
  })
end

--- Open the status window, or focus the one this store already has.
---@return integer buf
function M.open()
  local key = queue.key()
  render.define()

  local buf = M.buffer(key)
  local win = window_for(buf)

  if win then
    vim.api.nvim_set_current_win(win)
  else
    origin = vim.api.nvim_get_current_win()

    if require("damnit").options.window.float then
      open_float(buf)
    else
      open_split(buf)
    end

    configure(vim.api.nvim_get_current_win())
  end

  M.refresh(key)

  return buf
end

--- The window `:Dam` was opened from, when it is still there.
---@return integer?
function M.origin()
  if origin and vim.api.nvim_win_is_valid(origin) then
    return origin
  end

  return nil
end

--- The model the window last drew.
---@param key string?
---@return damnit.Model?
function M.model(key)
  return models[key or queue.key()]
end

--- The buffer line the count-th entry of a section is on.
---@param section_kind string
---@param nth integer
---@return integer?
function M.line_of(section_kind, nth)
  local buf = buffers[queue.key()]
  if not buf then
    return nil
  end

  local sections = vim.b[buf].damnit_sections or {}
  local kinds = vim.b[buf].damnit_kinds or {}
  local seen = 0

  for index, owner in ipairs(sections) do
    if owner == section_kind and kinds[index] ~= "section" then
      seen = seen + 1

      if seen == nth then
        return index
      end
    end
  end

  -- A count past the end lands on the last entry, the way fugitive's jumps do.
  return seen > 0 and M.line_of(section_kind, seen) or nil
end

--- The model entry the cursor is on, with the section that holds it.
---@return { entry: table, section: damnit.Section }?
function M.entry_under_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "damstatus" then
    return nil
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}
  local model = M.model()

  if not model or kinds[lnum] == "section" or not sections[lnum] then
    return nil
  end

  for _, section in ipairs(model.sections) do
    if section.kind == sections[lnum] then
      local nth = 0

      for index = 1, lnum do
        if sections[index] == section.kind and kinds[index] ~= "section" then
          nth = nth + 1
        end
      end

      local entry = section.entries[nth]
      if entry then
        return { entry = entry, section = section }
      end
    end
  end

  return nil
end

---@param key string
---@param win integer
local function remember_folds(key, win)
  folded[key] = {}

  local buf = vim.api.nvim_win_get_buf(win)
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}

  vim.api.nvim_win_call(win, function()
    for index, kind in ipairs(kinds) do
      if kind == "section" then
        folded[key][sections[index]] = vim.fn.foldclosed(index) ~= -1
      end
    end
  end)
end

---@param key string
---@param win integer
local function apply_folds(key, win)
  local closed = folded[key] or {}
  local buf = vim.api.nvim_win_get_buf(win)
  local kinds = vim.b[buf].damnit_kinds or {}
  local sections = vim.b[buf].damnit_sections or {}

  vim.api.nvim_win_call(win, function()
    for index, kind in ipairs(kinds) do
      if kind == "section" and closed[sections[index]] then
        pcall(vim.cmd, index .. "foldclose")
      end
    end
  end)
end

---@param key string
---@param lines damnit.Line[]
local function draw(key, lines)
  local buf = buffers[key]
  local win = window_for(buf)
  local oid = nil
  local lnum = 1

  if win then
    lnum = vim.api.nvim_win_get_cursor(win)[1]
    oid = (vim.b[buf].damnit_oids or {})[lnum]
    remember_folds(key, win)
  end

  render.draw(buf, lines)

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
  apply_folds(key, win)
end

---@param key string
---@param status table
function M.redraw(key, status)
  local buf = buffers[key]
  if not buf or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  models[key] = status_model.build(status, remotes[key])

  draw(key, render.lines(models[key], { store = store_display(key), running = queue.running(key) }))
end

--- Ask dam for the status and redraw from the answer.
---@param key string?
function M.refresh(key)
  key = key or queue.key()

  -- Read once per store and cached. A failure leaves the cache empty rather
  -- than caching the failure, so the next refresh asks again.
  if remotes[key] == nil then
    queue.submit({
      args = { "remote", "list", "--json" },
      label = "remote list",
      on_done = function(data)
        remotes[key] = data
      end,
    })
  end

  queue.submit({
    args = { "status", "--json" },
    label = "status",
    on_done = function(status, err)
      if err then
        return message.report(err)
      end

      M.redraw(key, status)
    end,
  })
end

--- Forget the cached remote list, so the next refresh reads it again.
---@param key string?
function M.forget_remotes(key)
  remotes[key or queue.key()] = nil
end

--- Rewrite the header while something is running. One buffer, a few lines, no
--- dam call and no other buffer touched.
---@param key string
function M.tick(key)
  local buf = buffers[key]
  if not buf or not vim.api.nvim_buf_is_loaded(buf) or not models[key] then
    return
  end

  local lines = render.lines(models[key], { store = store_display(key), running = queue.running(key) })

  local headers = 0
  for _, line in ipairs(lines) do
    if line.kind ~= "header" then
      break
    end
    headers = headers + 1
  end

  local drawn = 0
  for _, kind in ipairs(vim.b[buf].damnit_kinds or {}) do
    if kind ~= "header" then
      break
    end
    drawn = drawn + 1
  end

  if headers ~= drawn then
    return draw(key, lines)
  end

  local text = {}
  for index = 1, headers do
    text[index] = lines[index].text
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, headers, false, text)
  vim.bo[buf].modifiable = false
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
