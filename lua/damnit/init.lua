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

local app

local function tick_the_status_window(key)
  require("damnit.window").tick(app, key)
end

local function client_for(record)
  return require("damnit.dam").new(record.options, record.process, record.say)
end

local function through_vim_notify(text, level)
  vim.notify(text, level)
end

app = {
  options = M.options,
  process = require("damnit.process"),
  say = require("damnit.message").new(through_vim_notify),
}
app.store = require("damnit.store").of(app.options)
app.dam = client_for(app)
app.queue = require("damnit.queue").new(app, tick_the_status_window)

function M.app()
  return app
end

local function forget_dams_filters_read_from_the_old_store()
  require("damnit.views").reset()
end

local function start_the_reader_reminders_ride_on()
  require("damnit.poll").start(app)
end

function M.setup(opts, ports)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})

  local old_dam = app.dam
  app.options = M.options
  app.process = ports and ports.process or app.process
  app.say = ports and ports.say or app.say
  app.store = require("damnit.store").of(app.options)
  app.dam = client_for(app)
  old_dam.close()

  forget_dams_filters_read_from_the_old_store()

  if M.options.reminders then
    start_the_reader_reminders_ride_on()
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
  return require("damnit.list").open(app, require("damnit.views").COMPLETED)
end

function M.pick(name)
  require("damnit.picker").pick(app, name)
end

function M.open(name)
  return require("damnit.views").resolve_then(app, name, function(spec)
    return require("damnit.list").open(app, spec)
  end)
end

return M
