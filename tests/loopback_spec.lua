-- The client against a loopback double.
--
-- The other specs replace `vim.system`, which proves the plugin's own logic but
-- not that the command line it builds is one curl accepts. These cases run the
-- real curl against a server this spec starts on 127.0.0.1, so the argv, the
-- stdin configuration file, the request that arrives and the response that
-- comes back are all real. No token and no network: the double answers, and the
-- token is a string made up here.

local client = require("damnit.client")
local todoist = require("damnit")

local SECRET = "0123456789abcdef0123456789abcdef01234567"

--- A one-request HTTP server on a port the operating system picks.
---
--- It answers the first request with `status` and `body`, records what arrived,
--- and shuts down. One request per case keeps the teardown trivial.
---@param status integer
---@param body string
---@param extra_headers string[]?
---@return integer port
---@return table received filled in when the request arrives
local function serve(status, body, extra_headers)
  local server = assert(vim.uv.new_tcp())
  local received = {}

  server:bind("127.0.0.1", 0)
  server:listen(1, function()
    local socket = assert(vim.uv.new_tcp())
    server:accept(socket)

    local request = ""
    socket:read_start(function(err, chunk)
      assert(not err, err)
      if not chunk then
        return
      end

      request = request .. chunk
      if not request:find("\r\n\r\n", 1, true) then
        return
      end

      received.request = request

      local head = { ("HTTP/1.1 %d Whatever"):format(status), "Content-Type: application/json" }
      vim.list_extend(head, extra_headers or {})
      head[#head + 1] = ("Content-Length: %d"):format(#body)

      socket:write(table.concat(head, "\r\n") .. "\r\n\r\n" .. body, function()
        socket:read_stop()
        socket:close()
        server:close()
      end)
    end)
  end)

  return server:getsockname().port, received
end

--- Point the plugin at a loopback base URL and run one request to completion.
---@param port integer
---@param run fun(done: fun(data: any?, err: damnit.Error?))
---@return any? data
---@return damnit.Error? err
local function against(port, run)
  vim.env.TODOIST_SPEC_TOKEN = SECRET
  todoist.options = {
    token_command = nil,
    token_env = "TODOIST_SPEC_TOKEN",
    base_url = ("http://127.0.0.1:%d/api/v1"):format(port),
    curl = "curl",
    timeout = 5,
  }
  todoist.setup({})

  local answer = nil
  run(function(data, err)
    answer = { data = data, err = err }
  end)

  vim.wait(5000, function()
    return answer ~= nil
  end, 5)

  assert(answer, "the request never answered")

  return answer.data, answer.err
end

return {
  ["fetches one task over the wire and decodes it"] = function()
    local port, received = serve(200, '{"id":"6XGgmFVcrG5RRjVr","content":"Buy milk","priority":1}')

    local task, err = against(port, function(done)
      client.get_task("6XGgmFVcrG5RRjVr", done)
    end)

    assert(err == nil, vim.inspect(err))
    assert(task.content == "Buy milk", vim.inspect(task))
    assert(received.request:find("GET /api/v1/tasks/6XGgmFVcrG5RRjVr ", 1, true), received.request)
    assert(received.request:find("Authorization: Bearer " .. SECRET, 1, true), "the header did not arrive")
  end,

  ["writes one task back as a JSON body"] = function()
    local port, received = serve(200, '{"id":"1","content":"Pay rent"}')

    local task, err = against(port, function(done)
      client.update_task("1", { content = "Pay rent" }, done)
    end)

    assert(err == nil, vim.inspect(err))
    assert(task.content == "Pay rent", vim.inspect(task))
    assert(received.request:find("POST /api/v1/tasks/1 ", 1, true), received.request)
    assert(received.request:find('{"content":"Pay rent"}', 1, true), received.request)
  end,

  ["makes one task with its content and its location over the wire"] = function()
    local port, received = serve(200, '{"id":"6XGg","content":"hold the width"}')

    local task, err = against(port, function(done)
      client.create_task({ content = "hold the width", description = "damnit.nvim lua/list.lua:42" }, done)
    end)

    assert(err == nil, vim.inspect(err))
    assert(task.id == "6XGg", vim.inspect(task))
    assert(received.request:find("POST /api/v1/tasks ", 1, true), received.request)
    assert(received.request:find('"description":"damnit.nvim lua/list.lua:42"', 1, true), received.request)
  end,

  ["reports a refused token as unauthorized and says nothing about it"] = function()
    local port = serve(401, '{"error":"Unauthorized","error_code":477}')

    local notifications = {}
    local real_notify = vim.notify
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    local ok, result = pcall(against, port, function(done)
      client.get_task("1", done)
    end)

    vim.notify = real_notify
    assert(ok, result)

    assert(#notifications == 1, vim.inspect(notifications))
    assert(not notifications[1]:find(SECRET, 1, true), "the notification carried the token")
    assert(notifications[1]:find("token_command", 1, true), notifications[1])
  end,
}
