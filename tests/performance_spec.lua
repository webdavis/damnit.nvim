local status_model = require("damnit.status_model")
local render = require("damnit.render")

local SAMPLES = 5

local function warn_rather_than_fail_when_the_median_is_over(name, target_ms, run)
  local samples = {}

  for _ = 1, SAMPLES do
    local began = vim.uv.hrtime()
    run()
    samples[#samples + 1] = (vim.uv.hrtime() - began) / 1e6
  end

  table.sort(samples)
  local median = samples[math.ceil(SAMPLES / 2)]

  if median > target_ms then
    io.write(("WARN %s took %.1fms, over its %.0fms target\n"):format(name, median, target_ms))
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

return {
  ["every phase is inside its target, or says which one is not"] = function()
    warn_rather_than_fail_when_the_median_is_over("modelling the document", 1, function()
      model = status_model.build(status, nil)
    end)

    warn_rather_than_fail_when_the_median_is_over("rendering lines and marks", 60, function()
      lines = render.lines(model, state)
    end)

    warn_rather_than_fail_when_the_median_is_over("a re-render after a write", 70, function()
      render.draw(buf, render.lines(status_model.build(status, nil), state))
    end)

    warn_rather_than_fail_when_the_median_is_over("status() on a redraw", 0.05, function()
      require("damnit.poll").status()
    end)

    require("damnit.poll").stop()

    assert(#lines > FAR_MORE_UPDATES_THAN_A_REAL_WORKING_LAYER_CARRIES, "the generated status really did render")
  end,
}
