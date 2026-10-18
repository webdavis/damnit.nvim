local status_lines = require("damnit.render.status_lines")
local status_model = require("damnit.status_model")
local status_fixture = require("helpers.status_fixture")

local fixture = status_fixture.read
local lines_of = status_fixture.lines_of
local STATE = status_fixture.STATE

return {
  ["says the remote list is unknown when it could not be read, not that there is none"] = function()
    local unread = status_model.build(fixture("default/status.json"), nil)
    local none = status_model.build(fixture("default/status.json"), { remotes = {} })

    assert(status_lines.lines(unread, STATE)[2].text == "Remotes: unknown", status_lines.lines(unread, STATE)[2].text)
    assert(
      status_lines.lines(none, STATE)[2].text == "Remotes: none configured",
      status_lines.lines(none, STATE)[2].text
    )
  end,

  ["says how long ago each remote pulled, against the clock in state"] = function()
    local lines = lines_of(fixture("full/status.json"))

    assert(
      lines[2].text == "Remotes: fake (1 unpushed, pulled 4m ago)  flaky (7 unpushed, never pulled)",
      lines[2].text
    )
  end,

  ["rounds a pull's age down to one unit and never into the future"] = function()
    local ages = {
      ["2026-09-20T09:59:30Z"] = "pulled just now",
      ["2026-09-20T10:05:00Z"] = "pulled just now",
      ["2026-09-20T07:00:00.123456Z"] = "pulled 3h ago",
      ["2026-09-18T09:00:00Z"] = "pulled 2d ago",
      ["2024-02-29T10:00:00Z"] = "pulled 934d ago",
    }

    for last_pull, expected in pairs(ages) do
      local model = status_model.build({}, { remotes = { { name = "r", last_pull = last_pull } } })
      local text = status_lines.lines(model, STATE)[2].text

      assert(text == ("Remotes: r (clean, %s)"):format(expected), last_pull .. ": " .. text)
    end
  end,

  ["words a pull's age the way dam remote list does"] = function()
    local ages = {
      { last_pull = "2026-09-20T09:30:00Z", expected = "pulled 30m ago" },
      { last_pull = "last tuesday", expected = "pulled" },
      { last_pull = nil, expected = "never pulled" },
    }

    for _, age in ipairs(ages) do
      local model = status_model.build({}, { remotes = { { name = "r", last_pull = age.last_pull } } })
      local text = status_lines.lines(model, STATE)[2].text

      assert(text == ("Remotes: r (clean, %s)"):format(age.expected), text)
    end
  end,
}
