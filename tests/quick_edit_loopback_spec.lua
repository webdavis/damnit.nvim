-- What a quick edit puts on the wire.
--
-- Real curl against a server this spec starts on 127.0.0.1, so the method, the
-- path and the JSON body of every write a quick edit makes are the ones the API
-- would see. No token and no network: the double answers, and the token is a
-- string made up here.

local client = require("todoist.client")
local todoist = require("todoist")

local SECRET = "0123456789abcdef0123456789abcdef01234567"

--- An HTTP server on a port the operating system picks, answering everything
--- with `body` and recording each request as its method, path and body.
---@param body string
---@return { port: integer, seen: string[], close: fun() }
local function serve(body)
  local server = assert(vim.uv.new_tcp())
  local double = { seen = {} }

  server:bind("127.0.0.1", 0)
  server:listen(16, function()
    local socket = assert(vim.uv.new_tcp())
    server:accept(socket)

    local request = ""
    socket:read_start(function(err, chunk)
      assert(not err, err)
      if not chunk then
        return
      end

      request = request .. chunk
      local head, sent = request:match("^(.-)\r\n\r\n(.*)$")
      if not head then
        return
      end

      local length = tonumber(head:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")) or 0
      if #sent < length then
        return
      end

      local method, target = head:match("^(%u+) (%S+)")
      table.insert(double.seen, vim.trim(("%s %s %s"):format(method, target, sent)))

      local head_lines = {
        "HTTP/1.1 200 Whatever",
        "Content-Type: application/json",
        ("Content-Length: %d"):format(#body),
        "Connection: close",
      }
      socket:write(table.concat(head_lines, "\r\n") .. "\r\n\r\n" .. body, function()
        socket:read_stop()
        socket:close()
      end)
    end)
  end)

  double.port = server:getsockname().port
  double.close = function()
    server:close()
  end

  return double
end

---@param double { port: integer }
local function point_at(double)
  vim.env.TODOIST_SPEC_TOKEN = SECRET
  todoist.options = {
    token_command = nil,
    token_env = "TODOIST_SPEC_TOKEN",
    base_url = ("http://127.0.0.1:%d/api/v1"):format(double.port),
    curl = "curl",
    timeout = 5,
    views = {},
  }
  todoist.setup({})
end

--- Make one call and wait for its answer.
---@param call fun(done: fun())
local function ask(call)
  local answered = false
  call(function()
    answered = true
  end)

  assert(
    vim.wait(5000, function()
      return answered
    end, 5),
    "the request never answered"
  )
end

return {
  ["each write lands on its own endpoint with its own body"] = function()
    local double = serve('{"id":"7","content":"Pay rent"}')
    point_at(double)

    ask(function(done)
      client.close_task("6XGg", done)
    end)
    ask(function(done)
      client.reopen_task("6XGg", done)
    end)
    ask(function(done)
      client.delete_task("6XGg", done)
    end)
    ask(function(done)
      client.update_task("6XGg", { priority = 3 }, done)
    end)
    ask(function(done)
      client.update_task("6XGg", { due_string = "next mon" }, done)
    end)
    ask(function(done)
      client.update_task("6XGg", { labels = { "home" } }, done)
    end)
    ask(function(done)
      client.move_task("6XGg", { section_id = "9" }, done)
    end)
    ask(function(done)
      client.quick_add("Pay rent tomorrow 9am p1 #Finances @home", done)
    end)

    double.close()

    assert(
      vim.deep_equal(double.seen, {
        "POST /api/v1/tasks/6XGg/close",
        "POST /api/v1/tasks/6XGg/reopen",
        "DELETE /api/v1/tasks/6XGg",
        'POST /api/v1/tasks/6XGg {"priority":3}',
        'POST /api/v1/tasks/6XGg {"due_string":"next mon"}',
        'POST /api/v1/tasks/6XGg {"labels":["home"]}',
        'POST /api/v1/tasks/6XGg/move {"section_id":"9"}',
        'POST /api/v1/tasks/quick {"text":"Pay rent tomorrow 9am p1 #Finances @home"}',
      }),
      vim.inspect(double.seen)
    )
  end,

  ["the label picker reads the account's labels off the list endpoint"] = function()
    local double = serve('{"results":[{"id":"1","name":"home","order":1}],"next_cursor":null}')
    point_at(double)

    local labels
    ask(function(done)
      client.get_labels(function(read)
        labels = read
        done()
      end)
    end)

    double.close()

    assert(#labels == 1 and labels[1].name == "home", vim.inspect(labels))
    assert(double.seen[1]:find("GET /api/v1/labels", 1, true), vim.inspect(double.seen))
  end,
}
