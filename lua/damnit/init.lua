-- damnit.nvim: the dam task store from inside the editor.
--
-- Options and nothing else, read when a call is made rather than copied into
-- the caller, so a `setup` later in a session changes the next call.

local M = {}

--- Every option at its default.
---@class damnit.Options
---@field views table<string, string> a view name to the dam query it runs
---@field picker "auto"|"fzf-lua"|"select" which front end the task search uses
---@field sidebar damnit.SidebarOptions how `toggle` puts a view beside your work
---@field refresh_interval integer seconds between the background reads behind `status()`
---@field reminders boolean whether a task with a time raises a notification when it comes due
---@field store string? the store to pass as `--store`, or nil for dam's own resolution
---@field config string? the config to pass as `--config`, or nil for dam's own resolution
---@field timeout integer seconds one `dam` call may run before it is stopped
---@field window damnit.WindowOptions how the status window opens
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

--- The sidebar's own options.
---@class damnit.SidebarOptions
---@field side "left"|"right" the edge the split sits on
---@field width integer columns the split is held at
---@field view string the name of the view it opens

--- The status window's own options.
---@class damnit.WindowOptions
---@field float boolean open a centred float instead of a horizontal split

---@param opts damnit.Options?
function M.setup(opts)
  -- Deep, so naming one sidebar option keeps the defaults of the others.
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})

  -- A handshake made under the old options is not the one the new options name.
  require("damnit.dam").forget()
end

--- Open the staging window, which is this plugin's default surface.
---
--- The function a keymap calls:
--- `vim.keymap.set("n", "<leader>Ts", require("damnit").open_status)`.
---@return integer buf
function M.open_status()
  return require("damnit.window").open()
end

--- Search one view's objects, in fzf-lua or `vim.ui.select`. No name follows
--- the screen: the view the list buffer is showing, or every open object.
---@param name string?
function M.pick(name)
  require("damnit.picker").pick(name)
end

--- Open one view in the current window, by the name `setup` or dam's own config
--- declares. No name means every open object.
---@param name string?
---@return integer? buf
function M.open(name)
  local spec = require("damnit.views").resolve(name)

  if spec then
    return require("damnit.list").open(spec)
  end
end

return M
