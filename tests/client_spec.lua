-- The client: how a raw response becomes a result, what each failure is called,
-- and that nothing on the path blocks the editor or carries the token.

local client = require("damnit.client")
local todoist = require("damnit")

local SECRET = "0123456789abcdef0123456789abcdef01234567"

---@param status integer
---@param headers string[]
---@param body string
---@return string
local function response(status, headers, body)
  local lines = { ("HTTP/1.1 %d Whatever"):format(status) }
  vim.list_extend(lines, headers)

  return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
end

--- Configure the plugin with an environment token and no real curl reachable.
local function configure()
  vim.env.TODOIST_SPEC_TOKEN = SECRET
  todoist.options = {
    token_command = nil,
    token_env = "TODOIST_SPEC_TOKEN",
    base_url = "https://api.example.invalid/api/v1",
    curl = "curl",
    timeout = 15,
  }
  todoist.setup({})
end

--- Run `spec` against a `vim.system` that answers with `out`, collecting the
--- spawn, the result and any notification.
---@param out table
---@param spec table
---@return table
local function call(out, spec)
  configure()

  local real_system, real_notify = vim.system, vim.notify
  local seen = { notifications = {} }

  vim.system = function(argv, opts, callback)
    seen.argv, seen.opts = argv, opts
    vim.schedule(function()
      callback(out)
    end)

    return { pid = 0 }
  end
  vim.notify = function(message)
    table.insert(seen.notifications, message)
  end

  local ok, err = pcall(client.request, spec, function(data, failure)
    seen.answered = true
    seen.data, seen.err = data, failure
  end)

  vim.wait(2000, function()
    return seen.answered == true
  end, 5)

  vim.system, vim.notify = real_system, real_notify
  assert(ok, err)
  assert(seen.answered, "the request never answered")

  return seen
end

local GET_TASK = { method = "GET", path = "/tasks/6XGgmFVcrG5RRjVr" }

return {
  ["splits a response into status, headers and body"] = function()
    local status, headers, body = client.parse_response(response(200, { "Retry-After: 7" }, '{"id":"1"}'))

    assert(status == 200, tostring(status))
    assert(headers["retry-after"] == "7", vim.inspect(headers))
    assert(body == '{"id":"1"}', body)
  end,

  ["reads past an informational block to the real response"] = function()
    local raw = "HTTP/1.1 100 Continue\r\n\r\n" .. response(201, {}, "{}")
    local status = client.parse_response(raw)

    assert(status == 201, tostring(status))
  end,

  ["decodes a successful body"] = function()
    local data, err = client.interpret({ code = 0, stdout = response(200, {}, '{"content":"Buy milk"}') })

    assert(err == nil, vim.inspect(err))
    assert(data.content == "Buy milk", vim.inspect(data))
  end,

  ["treats an empty success as a success"] = function()
    local data, err = client.interpret({ code = 0, stdout = response(204, {}, "") })

    assert(err == nil, vim.inspect(err))
    assert(data == true)
  end,

  ["calls a refused token unauthorized without describing it"] = function()
    local _, err = client.interpret({ code = 0, stdout = response(401, {}, '{"error":"Unauthorized"}') })

    assert(err.kind == "unauthorized", vim.inspect(err))
    assert(not err.message:find(SECRET, 1, true))
  end,

  ["reports a forbidden request with the API's own message"] = function()
    local _, err = client.interpret({ code = 0, stdout = response(403, {}, '{"error":"Feature not available"}') })

    assert(err.kind == "forbidden", vim.inspect(err))
    assert(err.message == "Feature not available", err.message)
  end,

  ["carries Retry-After off a rate limit"] = function()
    local _, err = client.interpret({ code = 0, stdout = response(429, { "Retry-After: 42" }, "") })

    assert(err.kind == "rate_limited", vim.inspect(err))
    assert(err.retry_after == 42, tostring(err.retry_after))
  end,

  ["separates a missing task from any other error"] = function()
    local _, err = client.interpret({ code = 0, stdout = response(404, {}, '{"error":"Not Found"}') })

    assert(err.kind == "not_found", vim.inspect(err))
  end,

  ["calls a curl that produced no response a network failure"] = function()
    local _, err = client.interpret({ code = 7, stdout = "", stderr = "curl: (7) Failed to connect\n" })

    assert(err.kind == "network", vim.inspect(err))
    assert(err.message:find("Failed to connect", 1, true), err.message)
  end,

  ["calls a body that is not JSON malformed"] = function()
    local _, err = client.interpret({ code = 0, stdout = response(200, {}, "<html>maintenance</html>") })

    assert(err.kind == "malformed", vim.inspect(err))
  end,

  ["retries a rate limit and a server error, and never a refused token"] = function()
    assert(client.is_transient({ kind = "rate_limited" }))
    assert(client.is_transient({ kind = "network" }))
    assert(client.is_transient({ kind = "http", status = 503 }))
    assert(not client.is_transient({ kind = "http", status = 400 }))
    assert(not client.is_transient({ kind = "unauthorized" }))
  end,

  ["waits as long as Retry-After asked, within a bound"] = function()
    assert(client.retry_delay({ kind = "rate_limited", retry_after = 3 }) == 3000)
    assert(client.retry_delay({ kind = "network" }) == 1000)
    assert(client.retry_delay({ kind = "rate_limited", retry_after = 900 }) == 10000)
  end,

  ["returns before its callback fires"] = function()
    configure()

    local real = vim.system
    local answered, released = false, nil

    vim.system = function(_, _, callback)
      released = callback

      return { pid = 0 }
    end

    local ok, err = pcall(client.request, GET_TASK, function()
      answered = true
    end)

    vim.wait(500, function()
      return released ~= nil
    end, 5)

    local answered_on_return = answered
    if released then
      released({ code = 0, stdout = response(200, {}, "{}") })
    end

    vim.wait(2000, function()
      return answered
    end, 5)

    vim.system = real
    assert(ok, err)
    assert(released, "no request was made")
    assert(not answered_on_return, "the callback ran before the request returned")
    assert(answered, "the callback never ran")
  end,

  ["hands the token to curl on its standard input and never in its argv"] = function()
    local seen = call({ code = 0, stdout = response(200, {}, "{}") }, GET_TASK)

    assert(seen.opts.stdin:find(SECRET, 1, true), "the token did not reach curl")
    assert(seen.opts.stdin:find("Authorization: Bearer", 1, true), seen.opts.stdin)
    assert(not table.concat(seen.argv, " "):find(SECRET, 1, true), "the token was in the argv")
  end,

  ["builds the request out of the configured base URL"] = function()
    local seen = call({ code = 0, stdout = response(200, {}, "{}") }, {
      method = "GET",
      path = "/tasks/filter",
      query = { query = "today | overdue", limit = 50 },
    })

    local url = seen.argv[#seen.argv]
    assert(url:find("https://api.example.invalid/api/v1/tasks/filter?", 1, true), url)
    -- Percent-escaped, so a filter query survives the URL: Neovim writes the
    -- hex in lower case.
    assert(url:find("query=today%%20%%7[Cc]%%20overdue"), url)
    assert(url:find("limit=50", 1, true), url)
  end,

  ["sends an update as a JSON body"] = function()
    local seen = call({ code = 0, stdout = response(200, {}, "{}") }, {
      method = "POST",
      path = "/tasks/1",
      body = { content = "Pay rent", priority = 4 },
    })

    local argv = table.concat(seen.argv, " ")
    assert(argv:find("--request POST", 1, true), argv)
    assert(argv:find('"content":"Pay rent"', 1, true), argv)
  end,

  ["notifies once on a failure, without the token, unless asked to be quiet"] = function()
    local loud = call({ code = 0, stdout = response(403, {}, '{"error":"Feature not available"}') }, GET_TASK)

    assert(#loud.notifications == 1, vim.inspect(loud.notifications))
    assert(loud.notifications[1]:find("Feature not available", 1, true), loud.notifications[1])
    assert(not loud.notifications[1]:find(SECRET, 1, true), "the notification carried the token")

    local quiet = call({ code = 0, stdout = response(403, {}, "{}") }, {
      method = "GET",
      path = "/tasks/1",
      quiet = true,
    })

    assert(#quiet.notifications == 0, vim.inspect(quiet.notifications))
    assert(quiet.err.kind == "forbidden", vim.inspect(quiet.err))
  end,

  ["retries a transient failure once, then succeeds"] = function()
    configure()

    local real_system, real_notify, real_defer_fn = vim.system, vim.notify, vim.defer_fn
    local spawns = 0

    vim.system = function(_, _, callback)
      spawns = spawns + 1
      local out = spawns == 1 and { code = 0, stdout = response(503, {}, "") }
        or { code = 0, stdout = response(200, {}, '{"content":"ok"}') }

      vim.schedule(function()
        callback(out)
      end)

      return { pid = 0 }
    end
    -- Runs the retry immediately: the delay itself belongs to retry_delay's
    -- own test, not to this one.
    vim.defer_fn = function(fn)
      fn()
    end
    vim.notify = function() end

    local answered, data, err
    local ok, e = pcall(client.request, GET_TASK, function(d, failure)
      answered, data, err = true, d, failure
    end)

    vim.wait(2000, function()
      return answered == true
    end, 5)

    vim.system, vim.notify, vim.defer_fn = real_system, real_notify, real_defer_fn
    assert(ok, e)
    assert(spawns == 2, ("curl was spawned %d times"):format(spawns))
    assert(err == nil, vim.inspect(err))
    assert(data.content == "ok", vim.inspect(data))
  end,

  ["never retries a refused token"] = function()
    configure()

    local real_system, real_notify = vim.system, vim.notify
    local spawns = 0

    vim.system = function(_, _, callback)
      spawns = spawns + 1
      vim.schedule(function()
        callback({ code = 0, stdout = response(401, {}, '{"error":"Unauthorized"}') })
      end)

      return { pid = 0 }
    end
    vim.notify = function() end

    local answered, err
    local ok, e = pcall(client.request, GET_TASK, function(_, failure)
      answered, err = true, failure
    end)

    vim.wait(2000, function()
      return answered == true
    end, 5)

    vim.system, vim.notify = real_system, real_notify
    assert(ok, e)
    assert(spawns == 1, ("curl was spawned %d times"):format(spawns))
    assert(err.kind == "unauthorized", vim.inspect(err))
  end,

  ["forgets a refused token so the next request asks the source again"] = function()
    -- The token comes from a command here, so the number of times the source
    -- ran is visible: a cached token would show one run across two requests.
    todoist.options = {
      token_command = { "vault", "show", "todoist" },
      token_env = nil,
      base_url = "https://api.example.invalid/api/v1",
      curl = "curl",
      timeout = 15,
    }
    todoist.setup({})

    local real_system, real_notify = vim.system, vim.notify
    local vault_runs, answers = 0, 0
    local status = 401

    vim.system = function(argv, _, callback)
      local out
      if argv[1] == "vault" then
        vault_runs = vault_runs + 1
        out = { code = 0, stdout = SECRET .. "\n" }
      else
        out = { code = 0, stdout = response(status, {}, "{}") }
      end

      vim.schedule(function()
        callback(out)
      end)

      return { pid = 0 }
    end
    vim.notify = function() end

    local ok, err = pcall(function()
      client.request(GET_TASK, function()
        answers = answers + 1
        status = 200
        client.request(GET_TASK, function()
          answers = answers + 1
        end)
      end)

      vim.wait(2000, function()
        return answers == 2
      end, 5)
    end)

    vim.system, vim.notify = real_system, real_notify
    assert(ok, err)
    assert(answers == 2, ("%d requests answered"):format(answers))
    assert(vault_runs == 2, ("the token source ran %d times"):format(vault_runs))
  end,
}
