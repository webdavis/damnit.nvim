local M = {}

local PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP = require("helpers.paths").TESTS .. "/../plugin/damnit.lua"
dofile(PLUGIN_FILE_THAT_DECLARES_DAM_RATHER_THAN_SETUP)

local harness = require("helpers.harness")
local window = require("damnit.window")

function M.opts(extra)
  return vim.tbl_extend("force", { fixtures = harness.fixtures("full"), open = window.open }, extra or {})
end

function M.answering(answer, on_prompt)
  return function(opts, on_answer)
    if on_prompt then
      on_prompt(opts.prompt)
    end
    on_answer(answer)
  end
end

return M
