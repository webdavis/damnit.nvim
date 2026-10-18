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

local function tick_the_status_window(key)
  require("damnit.window").tick(key)
end

local function client_for(app)
  return require("damnit.dam").new(app.options, app.process)
end

local app = { options = M.options, process = require("damnit.process") }
app.dam = client_for(app)
app.queue = require("damnit.queue").new(app, tick_the_status_window)

function M.app()
  return app
end

local function forget_dams_filters_read_from_the_old_store()
  require("damnit.views").reset()
end

local function start_the_reader_reminders_ride_on()
  require("damnit.poll").start()
end

function M.setup(opts, ports)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})

  local old_dam = app.dam
  app.options = M.options
  app.process = ports and ports.process or app.process
  app.dam = client_for(app)
  old_dam.close()

  forget_dams_filters_read_from_the_old_store()

  if M.options.reminders then
    start_the_reader_reminders_ride_on()
  end
end

function M.status()
  return require("damnit.poll").status()
end

function M.open_status()
  return require("damnit.window").open()
end

function M.toggle()
  require("damnit.sidebar").toggle()
end

function M.completed()
  return require("damnit.list").open({ title = "completed", query = "done", flat = true })
end

function M.pick(name)
  require("damnit.picker").pick(name)
end

function M.open(name)
  return require("damnit.views").resolve_then(name, require("damnit.list").open)
end

return M
