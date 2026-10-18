local M = {}

local actions = require("damnit.actions")
local done = require("damnit.done")
local help = require("damnit.help")
local keymaps = require("damnit.keymaps")
local list = require("damnit.list")
local quick_edit = require("damnit.quick_edit")
local send = require("damnit.send")
local sync = require("damnit.sync")

local FEATURES = {
  actions = actions,
  done = done,
  help = help,
  list = list,
  quick_edit = quick_edit,
  send = send,
  sync = sync,
}

function M.attach(buf, filetype, app)
  for _, map in ipairs(keymaps.MAPS[filetype] or {}) do
    local run = FEATURES[map.run.feature][map.run.name]

    vim.keymap.set(map.mode, map.lhs, function()
      run(app, unpack(map.run.args))
    end, { buffer = buf, nowait = true, desc = "dam: " .. map.desc })
  end
end

return M
