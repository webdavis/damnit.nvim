-- The version handshake: what the plugin accepts, what it refuses for the rest
-- of the session, and what it shrugs at.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local dam = require("damnit.dam")

---@param version string what the fake prints for `dam --version`
---@return damnit.Error? err
---@return string[] notifications
---@return string[] argv_log
local function first_call(version)
  local fake = fake_dam.install({ version = version })

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local answered, err = false, nil
  dam.call({ "status", "--json" }, nil, function(_, failure)
    answered, err = true, failure
  end)

  fake_dam.settle(function()
    return answered
  end)

  vim.notify = real
  local log = fake_dam.argv_log(fake)
  fake_dam.remove(fake)

  return err, notifications, log
end

return {
  ["accepts 0.2.0 and goes on to make the call"] = function()
    local err, _, log = first_call("0.2.0")

    assert(err == nil, err and err.message)
    assert(log[1] == "--version", vim.inspect(log))
    assert(log[2] == "status --json", vim.inspect(log))
  end,

  ["refuses a version above the range and never spawns the call"] = function()
    local err, _, log = first_call("0.9.0")

    assert(err.kind == "unsupported", vim.inspect(err))
    assert(err.message == "dam 0.9.0 is outside the supported range >=0.2.0 <0.3.0; update damnit.nvim", err.message)
    assert(#log == 1 and log[1] == "--version", vim.inspect(log))
  end,

  ["refuses 0.3.0, which is the first version outside the range"] = function()
    assert(dam.supported("0.2.0"))
    assert(dam.supported("0.2.9"))
    assert(not dam.supported("0.3.0"))
    assert(not dam.supported("0.1.9"))
  end,

  ["warns once about a banner it cannot read, then makes the call anyway"] = function()
    local err, notifications, log = first_call("banana")

    assert(err == nil, err and err.message)
    assert(#notifications == 1, vim.inspect(notifications))
    assert(notifications[1]:find("is not a version", 1, true), notifications[1])
    assert(log[2] == "status --json", vim.inspect(log))
  end,

  ["runs the handshake once per session, not once per call"] = function()
    local fake = fake_dam.install()

    for _ = 1, 3 do
      local answered = false
      dam.call({ "status", "--json" }, nil, function()
        answered = true
      end)
      fake_dam.settle(function()
        return answered
      end)
    end

    local log = fake_dam.argv_log(fake)
    fake_dam.remove(fake)

    local versions = 0
    for _, line in ipairs(log) do
      if line == "--version" then
        versions = versions + 1
      end
    end

    assert(versions == 1, vim.inspect(log))
  end,
}
