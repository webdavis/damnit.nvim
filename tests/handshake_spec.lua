local with_dam = require("helpers.harness").with_dam
local fake_process = require("helpers.fake_process")

local function client()
  return require("damnit").app().dam
end

local said = require("helpers.said")

local function first_call_to_a_dam_whose_version_says(version_banner)
  local answered, err = false, nil

  local dam = with_dam({ version = version_banner }, function()
    client().call({ "status", "--json" }, nil, function(_, failure)
      answered, err = true, failure
    end)

    fake_process.settle(function()
      return answered
    end)
  end)

  return err, dam.said, dam.sent
end

return {
  ["accepts 0.2.0 and goes on to make the call"] = function()
    local err, _, log = first_call_to_a_dam_whose_version_says("0.2.0")

    assert(err == nil, err and err.message)
    assert(log[1] == "--version", vim.inspect(log))
    assert(log[2] == "status --json", vim.inspect(log))
  end,

  ["refuses a version above the range and never spawns the call"] = function()
    local err, _, log = first_call_to_a_dam_whose_version_says("0.9.0")

    assert(err.kind == "unsupported", vim.inspect(err))
    assert(err.message == "dam 0.9.0 is outside the supported range >=0.2.0 <0.3.0; update damnit.nvim", err.message)
    assert(#log == 1 and log[1] == "--version", vim.inspect(log))
  end,

  ["refuses 0.3.0, which is the first version outside the range"] = function()
    assert(require("damnit.dam").supported("0.2.0"))
    assert(require("damnit.dam").supported("0.2.9"))
    assert(not require("damnit.dam").supported("0.3.0"))
    assert(not require("damnit.dam").supported("0.1.9"))
  end,

  ["warns once about a banner it cannot read, then makes the call anyway"] = function()
    local err, notifications, log = first_call_to_a_dam_whose_version_says("banana")

    assert(err == nil, err and err.message)
    assert(#notifications == 1, vim.inspect(notifications))
    assert(
      said.whole(
        notifications[1],
        'damnit.nvim: dam --version printed "dam banana", which is not a version; going on anyway'
      ),
      notifications[1]
    )
    assert(log[2] == "status --json", vim.inspect(log))
  end,

  ["runs the handshake once per session, not once per call"] = function()
    with_dam({}, function(dam)
      for _ = 1, 3 do
        local answered = false
        client().call({ "status", "--json" }, nil, function()
          answered = true
        end)
        fake_process.settle(function()
          return answered
        end)
      end

      local log = fake_process.argv_log(dam.fake)

      local versions = 0
      for _, line in ipairs(log) do
        if line == "--version" then
          versions = versions + 1
        end
      end

      assert(versions == 1, vim.inspect(log))
    end)
  end,
}
