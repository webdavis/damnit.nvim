local M = {}

M.options = {
  views = {},
  picker = "auto",
  sidebar = {
    side = "left",
    width = 40,
    view = "today",
  },
  refresh_interval = 60,
  reminders = false,
  timeout = 120,
  window = {
    float = false,
  },
}

local autocmds = require("damnit.autocmds")
local dam = require("damnit.dam")
local message = require("damnit.message")
local process = require("damnit.process")
local queue = require("damnit.queue")
local store = require("damnit.store")
local views = require("damnit.views")

local app

local tick_the_status_window_once_it_is_loaded = autocmds.once_loaded("damnit.window", function(window, key)
  window.tick(app, key)
end)

local function through_vim_notify(text, level)
  vim.notify(text, level)
end

local function client_for(record)
  return dam.new(record.options, record.process, record.say)
end

app = { options = M.options, process = process, say = message.new(through_vim_notify) }
app.store = store.of(app.options)
app.dam = client_for(app)
app.queue = queue.new(app, tick_the_status_window_once_it_is_loaded)
autocmds.setup(app)

function M.app()
  return app
end

function M.setup(opts, ports)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})

  local old_dam = app.dam
  app.options = M.options
  app.process = ports and ports.process or app.process
  app.say = ports and ports.say or app.say
  app.store = store.of(app.options)
  app.dam = client_for(app)
  old_dam.close()

  views.reset()

  if M.options.reminders then
    require("damnit.poll").start(app)
  end
end

function M.status()
  return require("damnit.poll").status(app)
end

function M.open_status()
  return require("damnit.window").open(app)
end

function M.toggle()
  require("damnit.sidebar").toggle(app)
end

function M.completed()
  return require("damnit.list").open(app, views.COMPLETED)
end

function M.pick(name)
  require("damnit.picker").pick(app, name)
end

function M.open(name)
  return views.resolve_then(app, name, function(spec)
    return require("damnit.list").open(app, spec)
  end)
end

return M
