local M = {}

local keymaps = require("damnit.keymaps")

function M.attach(buf, filetype, app)
  for _, map in ipairs(keymaps.MAPS[filetype] or {}) do
    local run = require("damnit." .. map.run.feature)[map.run.name]

    vim.keymap.set(map.mode, map.lhs, function()
      run(app, unpack(map.run.args))
    end, { buffer = buf, nowait = true, desc = "dam: " .. map.desc })
  end
end

return M
