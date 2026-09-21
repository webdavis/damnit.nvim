-- The dam boundary: the argv it builds, the JSON it decodes, and the error
-- table it makes of every exit code.

local fake_dam = dofile((arg[0]:match("(.*)/") or ".") .. "/helpers/fake_dam.lua")
local dam = require("damnit.dam")
local damnit = require("damnit")

---@param opts table? passed to fake_dam.install
---@param args string[]
---@return table? data
---@return damnit.Error? err
---@return string[] argv_log
local function call(opts, args)
  local fake = fake_dam.install(opts)

  local answered, data, err = false, nil, nil
  dam.call(args, nil, function(value, failure)
    answered, data, err = true, value, failure
  end)

  fake_dam.settle(function()
    return answered
  end)

  local log = fake_dam.argv_log(fake)
  fake_dam.remove(fake)

  return data, err, log
end

return {
  ["builds an argv with no store flags when neither option is set"] = function()
    damnit.options.store, damnit.options.config = nil, nil

    assert(vim.deep_equal(dam.argv({ "status", "--json" }), { "dam", "status", "--json" }))
  end,

  ["passes --store and --config through as global flags, before the subcommand"] = function()
    damnit.options.store, damnit.options.config = "/store/dam.db", "/config/dam.toml"

    local argv = dam.argv({ "status", "--json" })
    damnit.options.store, damnit.options.config = nil, nil

    assert(
      vim.deep_equal(argv, {
        "dam",
        "--store",
        "/store/dam.db",
        "--config",
        "/config/dam.toml",
        "status",
        "--json",
      }),
      vim.inspect(argv)
    )
  end,

  ["decodes the JSON dam printed on a clean exit"] = function()
    local data, err, log = call(nil, { "status", "--json" })

    assert(err == nil, err and err.message)
    assert(type(data) == "table" and vim.islist(data.staged), vim.inspect(data))
    assert(log[#log] == "status --json", vim.inspect(log))
  end,

  ["calls exit 1 an error and strips dam's own prefix off the line"] = function()
    local _, err = call({ exit = 1, stderr = "dam: storage: the store is locked" }, { "add", "78b8950", "--json" })

    assert(err.kind == "error", err.kind)
    assert(err.code == 1, tostring(err.code))
    assert(err.message == "storage: the store is locked", err.message)
    assert(err.plugin == nil, "dam wrote this message, so it takes no prefix")
  end,

  ["calls exit 2 a refusal and keeps every line of a multi-line one"] = function()
    local stderr = "dam: 98d8780 cannot be completed:\n  child a9db854 is open"
    local _, err = call({ exit = 2, stderr = stderr }, { "done", "98d8780", "--json" })

    assert(err.kind == "refused", err.kind)
    assert(err.message == "98d8780 cannot be completed:\n  child a9db854 is open", vim.inspect(err.message))
  end,

  ["calls exit 3 cancelled"] = function()
    local _, err = call({ exit = 3, stderr = "dam: cancelled" }, { "push", "--json" })

    assert(err.kind == "cancelled", err.kind)
    assert(err.code == 3, tostring(err.code))
  end,

  ["reads a call a signal killed as cancelled, whichever signal it was"] = function()
    for name, signal in pairs({ sigint = 2, sigterm = 15, sigkill = 9 }) do
      local _, err = dam.interpret({ code = 0, signal = signal, stdout = "", stderr = "" }, "push todoist")

      assert(err ~= nil and err.kind == "cancelled", name .. ": " .. vim.inspect(err))
      assert(err.code == 3, name .. ": " .. tostring(err.code))
    end
  end,

  ["says who was stopped when the signal left no message behind"] = function()
    local _, err = dam.interpret({ code = 0, signal = 9, stdout = "", stderr = "" }, "push todoist")

    assert(err.message == "push todoist was stopped", err.message)
    assert(err.plugin == true, "the plugin wrote this one")
  end,

  ["keeps dam's own word for the cancellation when it managed to write one"] = function()
    local out = { code = 0, signal = 2, stdout = "", stderr = "dam: cancelled" }
    local _, err = dam.interpret(out, "push todoist")

    assert(err.message == "cancelled", err.message)
    assert(err.plugin == nil, "dam wrote this message, so it takes no prefix")
  end,

  ["keeps the timeout on its own path, signal and all"] = function()
    local _, err = dam.interpret({ code = 124, signal = 15, stdout = "", stderr = "" }, "push todoist")

    assert(err.kind == "timeout", vim.inspect(err))
    assert(err.code == 124, tostring(err.code))
    assert(err.message:find("took longer than", 1, true), err.message)
  end,

  ["calls an undecodable answer on a clean exit malformed rather than raising"] = function()
    local fake = fake_dam.install()
    vim.env.DAMNIT_TEST_FIXTURES = fake.dir

    local file = assert(io.open(fake.dir .. "/status.json", "w"))
    file:write("not json at all\n")
    file:close()

    local answered, err = false, nil
    dam.call({ "status", "--json" }, nil, function(_, failure)
      answered, err = true, failure
    end)

    fake_dam.settle(function()
      return answered
    end)
    fake_dam.remove(fake)

    assert(err.kind == "malformed", vim.inspect(err))
    assert(err.plugin == true, "the plugin wrote this one")
  end,

  ["reports a dam that is not on PATH instead of raising"] = function()
    local saved = vim.env.PATH
    vim.env.PATH = "/nonexistent-for-this-spec"
    dam.forget()

    local answered, err = false, nil
    local ok = pcall(dam.call, { "status", "--json" }, nil, function(_, failure)
      answered, err = true, failure
    end)

    fake_dam.settle(function()
      return answered
    end)

    vim.env.PATH = saved
    dam.forget()

    assert(ok, "a missing binary must not raise out of dam.call")
    assert(err.kind == "missing", vim.inspect(err))
    assert(err.message:find("cargo install damnit", 1, true), err.message)
  end,
}
