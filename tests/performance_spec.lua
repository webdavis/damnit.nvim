local status_model = require("damnit.status_model")
local render = require("damnit.render")

--- Time `run` five times and warn when the median is over `target_ms`.
local function phase(name, target_ms, run)
  local samples = {}

  for _ = 1, 5 do
    local began = vim.uv.hrtime()
    run()
    samples[#samples + 1] = (vim.uv.hrtime() - began) / 1e6
  end

  table.sort(samples)
  local median = samples[3]

  if median > target_ms then
    io.write(("WARN %s took %.1fms, over its %.0fms target\n"):format(name, median, target_ms))
  end
end

--- A working layer of `count` updated tasks, in the row shape dam 0.2.0 writes:
--- flat fields on the change itself, with `fields` naming what differs.
---
--- 300 is far more than a real store carries into one working layer, and the
--- cost is linear in it: `render.lines` measures each segment's display width
--- through `vim.fn`, one bridge call per segment.
local function generated(count)
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

local status = generated(300)
local state = { store = "perf" }
local model = nil
local lines = nil
local buf = vim.api.nvim_create_buf(false, true)

return {
  ["every phase is inside its target, or says which one is not"] = function()
    phase("modelling the document", 1, function()
      model = status_model.build(status, nil)
    end)

    phase("rendering lines and marks", 60, function()
      lines = render.lines(model, state)
    end)

    phase("a re-render after a write", 70, function()
      render.draw(buf, render.lines(status_model.build(status, nil), state))
    end)

    phase("status() on a redraw", 0.05, function()
      require("damnit.poll").status()
    end)

    require("damnit.poll").stop()

    assert(#lines > 300, "the generated status really did render")
  end,
}
