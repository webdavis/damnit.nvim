local M = {}

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = require("helpers.paths").TESTS .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local damnit = require("damnit")
local harness = require("helpers.harness")

function M.opts(opts)
  opts = opts or {}

  return {
    fixtures = opts.fixtures or harness.fixtures("full"),
    exit = opts.exit,
    stderr = opts.stderr,
    input = opts.input,
    select = opts.select,
    options = { views = opts.views or {} },
    open = opts.open or function()
      return damnit.open(opts.name)
    end,
  }
end

function M.cursor_to(buf, needle)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(needle, 1, true) then
      vim.api.nvim_win_set_cursor(0, { index, 0 })

      return
    end
  end

  error("no line holds " .. needle)
end

return M
