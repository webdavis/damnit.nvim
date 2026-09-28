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

local function forget_the_handshake_made_under_old_options()
  require("damnit.dam").forget()
end

local function start_the_reader_reminders_ride_on()
  require("damnit.poll").start()
end

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})

  forget_the_handshake_made_under_old_options()

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
  local spec = require("damnit.views").resolve(name)

  if spec then
    return require("damnit.list").open(spec)
  end
end

return M
