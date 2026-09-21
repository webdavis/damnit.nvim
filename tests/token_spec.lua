-- The token boundary: where a token may come from, and what a failure is
-- allowed to say about it.

local todoist = require("damnit")
local token = require("damnit.token")

local SECRET = "0123456789abcdef0123456789abcdef01234567"

--- Fresh options with no token source, and no token remembered from a case that
--- ran before this one.
---@param options table?
local function configure(options)
  todoist.options = {
    token = nil,
    token_command = nil,
    token_env = nil,
    base_url = "http://127.0.0.1:1",
    curl = "curl",
    timeout = 15,
  }
  todoist.setup(options or {})
end

--- Resolve and hand back the pair, pumping the loop for the command path.
---@return string? resolved
---@return string? err
local function resolve()
  local answer = nil
  token.resolve(todoist.options, function(value, err)
    answer = { value = value, err = err }
  end)

  vim.wait(2000, function()
    return answer ~= nil
  end, 5)

  assert(answer, "resolve never answered")

  return answer.value, answer.err
end

--- Stand in for `vim.system` while `run` executes, answering every spawn with
--- one canned result.
---@param result table
---@param run fun()
---@return table[] spawns
local function with_system(result, run)
  local real = vim.system
  local spawns = {}

  vim.system = function(argv, opts, callback)
    table.insert(spawns, { argv = argv, opts = opts })
    vim.schedule(function()
      callback(result)
    end)

    return { pid = 0 }
  end

  local ok, err = pcall(run)
  vim.system = real

  assert(ok, err)

  return spawns
end

return {
  ["reads the token out of the environment variable token_env names"] = function()
    vim.env.TODOIST_SPEC_TOKEN = SECRET
    configure({ token_env = "TODOIST_SPEC_TOKEN" })

    local resolved, err = resolve()

    assert(err == nil, tostring(err))
    assert(resolved == SECRET, tostring(resolved))
  end,

  ["names the variable, and nothing else, when token_env is not set"] = function()
    vim.env.TODOIST_SPEC_MISSING = nil
    configure({ token_env = "TODOIST_SPEC_MISSING" })

    local resolved, err = resolve()

    assert(resolved == nil)
    assert(err:find("TODOIST_SPEC_MISSING", 1, true), err)
  end,

  ["refuses to work with no token source at all"] = function()
    configure({})

    local resolved, err = resolve()

    assert(resolved == nil)
    assert(err:find("token_command", 1, true) and err:find("token_env", 1, true), err)
    assert(err:find("token to the token itself", 1, true), err)
  end,

  ["runs token_command and takes the first line of its standard output"] = function()
    configure({ token_command = { "vault", "show", "todoist" } })

    local resolved, err
    local spawns = with_system({ code = 0, stdout = SECRET .. "\n" }, function()
      resolved, err = resolve()
    end)

    assert(err == nil, tostring(err))
    assert(resolved == SECRET, tostring(resolved))
    assert(spawns[1].argv[1] == "vault", vim.inspect(spawns[1].argv))
  end,

  ["reports a failed token_command by exit code and never quotes its output"] = function()
    configure({ token_command = { "vault", "show", "todoist" } })

    local resolved, err
    with_system({ code = 2, stdout = SECRET, stderr = SECRET }, function()
      resolved, err = resolve()
    end)

    assert(resolved == nil)
    assert(err:find("exited 2", 1, true), err)
    assert(not err:find(SECRET, 1, true), "the message carried the command's output")
  end,

  ["refuses a value that could not be carried to curl unchanged"] = function()
    configure({ token_command = { "vault" } })

    local resolved, err
    with_system({ code = 0, stdout = 'not"a token\n' }, function()
      resolved, err = resolve()
    end)

    assert(resolved == nil)
    assert(not err:find('not"a token', 1, true), "the message quoted the value")
    assert(err:find("not a token", 1, true), err)
  end,

  ["remembers a resolved token, and forgets it on demand"] = function()
    configure({ token_command = { "vault" } })

    local spawns = with_system({ code = 0, stdout = SECRET }, function()
      resolve()
      resolve()
      token.forget()
      resolve()
    end)

    assert(#spawns == 2, ("token_command ran %d times"):format(#spawns))
  end,

  ["forgets a resolved token when setup is called again"] = function()
    configure({ token_command = { "vault" } })

    local spawns = with_system({ code = 0, stdout = SECRET }, function()
      resolve()
      configure({ token_command = { "vault" } })
      resolve()
    end)

    assert(#spawns == 2, ("token_command ran %d times"):format(#spawns))
  end,

  ["takes the token straight out of the token option"] = function()
    configure({ token = SECRET })

    local resolved, err = resolve()

    assert(err == nil, tostring(err))
    assert(resolved == SECRET, tostring(resolved))
  end,

  ["refuses a token option that is not a string"] = function()
    configure({ token = 42 })

    local resolved, err = resolve()

    assert(resolved == nil)
    assert(err:find("string", 1, true), err)
  end,

  ["holds the token option to the same carriable rule as a command"] = function()
    configure({ token = 'not"a token' })

    local resolved, err = resolve()

    assert(resolved == nil)
    assert(not err:find('not"a token', 1, true), "the message quoted the value")
    assert(err:find("not a token", 1, true), err)
  end,

  ["prefers the token option over token_command and spawns nothing"] = function()
    configure({ token = SECRET, token_command = { "vault" } })

    local resolved, err
    local spawns = with_system({ code = 0, stdout = "a-different-token" }, function()
      resolved, err = resolve()
    end)

    assert(err == nil, tostring(err))
    assert(resolved == SECRET, tostring(resolved))
    assert(#spawns == 0, ("token_command ran %d times"):format(#spawns))
  end,

  ["prefers token_command over token_env"] = function()
    vim.env.TODOIST_SPEC_TOKEN = "a-different-token"
    configure({ token_command = { "vault" }, token_env = "TODOIST_SPEC_TOKEN" })

    local resolved, err
    with_system({ code = 0, stdout = SECRET }, function()
      resolved, err = resolve()
    end)

    assert(err == nil, tostring(err))
    assert(resolved == SECRET, tostring(resolved))
  end,
}
