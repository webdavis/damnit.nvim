local root = vim.fn.fnamemodify(arg[0], ":p:h:h:h")
package.path = ("%s/lua/?.lua;%s/lua/?/init.lua;%s"):format(root, root, package.path)

local status_model = require("damnit.status_model")
local render = require("damnit.render")

local SAMPLES = 5

local over_target = 0

local function median_inside(name, target_ms, run)
  local samples = {}

  for _ = 1, SAMPLES do
    local began = vim.uv.hrtime()
    run()
    samples[#samples + 1] = (vim.uv.hrtime() - began) / 1e6
  end

  table.sort(samples)
  local median = samples[math.ceil(SAMPLES / 2)]

  local verdict = median > target_ms and "OVER" or "ok"
  io.write(("%s %s took %.3fms, target %.2fms\n"):format(verdict, name, median, target_ms))

  if median > target_ms then
    over_target = over_target + 1
  end
end

local FAR_MORE_UPDATES_THAN_A_REAL_WORKING_LAYER_CARRIES = 300

local function working_layer_of_flat_update_rows(count)
  local unstaged = {}

  for index = 1, count do
    local oid = ("%040x"):format(index)
    unstaged[index] = {
      oid = oid,
      op = "update",
      fields = { "subject", "priority" },
      kind = "task",
      subject = "task " .. index,
      path = "work/",
      labels = {},
      done = false,
      priority = 2,
      due = "2026-09-25",
    }
  end

  return { unstaged = unstaged, staged = {}, conflicts = {}, notices = {}, unpushed = {} }
end

local status = working_layer_of_flat_update_rows(FAR_MORE_UPDATES_THAN_A_REAL_WORKING_LAYER_CARRIES)
local state = { store = "perf" }
local model = nil
local lines = nil
local buf = vim.api.nvim_create_buf(false, true)

median_inside("modelling the document", 1, function()
  model = status_model.build(status, nil)
end)

median_inside("rendering lines and marks", 60, function()
  lines = render.lines(model, state)
end)

median_inside("a re-render after a write", 70, function()
  render.draw(buf, render.lines(status_model.build(status, nil), state))
end)

median_inside("status() on a redraw", 0.05, function()
  require("damnit.poll").status(require("damnit").app())
end)

require("damnit.poll").stop()

assert(#lines > FAR_MORE_UPDATES_THAN_A_REAL_WORKING_LAYER_CARRIES, "the generated status really did render")

os.exit(over_target == 0 and 0 or 1)
