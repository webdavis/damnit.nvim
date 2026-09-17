-- A view against a loopback double.
--
-- These cases run the real curl against a server this spec starts on 127.0.0.1,
-- so the three requests a list makes, the filter that travels on the query
-- string and the answer that comes back are all real. No token and no network:
-- the double answers, and the token is a string made up here.
--
-- The double answers by path, because a list asks for tasks, projects and
-- sections at once and a case cares which of them was refused.

local list = require("todoist.list")
local todoist = require("todoist")

local SECRET = "0123456789abcdef0123456789abcdef01234567"

local EMPTY_PAGE = '{"results":[],"next_cursor":null}'

--- An HTTP server on a port the operating system picks, answering each request
--- from `routes` keyed by path.
---
--- `close` waits for every request that arrived to be answered first. A list
--- makes three, and the two a refused filter no longer needs are still in
--- flight when the buffer is drawn: shutting the port under them would fail
--- them as network errors, and the client would raise that inside whichever
--- case happened to be running by then.
---@param routes table<string, { status: integer, body: string }>
---@return { port: integer, asked: string[], close: fun() }
local function serve(routes)
  local server = assert(vim.uv.new_tcp())
  local double = { asked = {}, answered = 0 }

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
      if not request:find("\r\n\r\n", 1, true) then
        return
      end

      local target = request:match("^%u+ (%S+)") or ""
      table.insert(double.asked, target)

      local route = routes[target:match("^[^?]*")] or { status = 404, body = '{"error":"no such route"}' }
      local head = {
        ("HTTP/1.1 %d Whatever"):format(route.status),
        "Content-Type: application/json",
        ("Content-Length: %d"):format(#route.body),
        "Connection: close",
      }

      local function answer()
        socket:write(table.concat(head, "\r\n") .. "\r\n\r\n" .. route.body, function()
          double.answered = double.answered + 1
          socket:read_stop()
          socket:close()
        end)
      end

      if route.delay_ms then
        vim.defer_fn(answer, route.delay_ms)
      else
        answer()
      end
    end)
  end)

  double.port = server:getsockname().port

  double.close = function()
    vim.wait(2000, function()
      return #double.asked >= 3 and double.answered == #double.asked
    end, 5)

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
    views = { today = "today | overdue", broken = "due befor: tomorrow" },
  }
  todoist.setup({})
end

--- Open one view and wait for the buffer to stop saying it is loading.
---@param name string?
---@return string[] lines
---@return string[] notifications raised while the view was loading
local function open(name)
  local notifications = {}
  local real_notify = vim.notify
  vim.notify = function(message)
    table.insert(notifications, message)
  end

  local ok, buf = pcall(todoist.open, name)
  if ok then
    ok = vim.wait(5000, function()
      local lines = vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
      return lines[3] ~= "Loading..."
    end, 5)
  end

  vim.notify = real_notify
  assert(ok, "the view never finished loading: " .. vim.inspect(buf))

  return vim.api.nvim_buf_get_lines(buf, 0, -1, false), notifications
end

---@param lines string[]
---@param needle string
local function has_line_with(lines, needle)
  for _, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return true
    end
  end

  return false
end

return {
  ["renders a view and maps each line back to its task id"] = function()
    local double = serve({
      ["/api/v1/tasks/filter"] = {
        status = 200,
        body = '{"results":[{"id":"6XGg","content":"Buy milk","project_id":"1","section_id":"9","priority":3,'
          .. '"labels":["errands"],"due":{"date":"2026-09-17","string":"today"}}],"next_cursor":null}',
      },
      ["/api/v1/projects"] = { status = 200, body = '{"results":[{"id":"1","name":"Errands"}],"next_cursor":null}' },
      ["/api/v1/sections"] = {
        status = 200,
        body = '{"results":[{"id":"9","project_id":"1","name":"Saturday"}],"next_cursor":null}',
      },
    })
    point_at(double)

    local lines = open("today")
    double.close()

    assert(has_line_with(lines, "Todoist: today  (today | overdue)"), vim.inspect(lines))
    assert(has_line_with(lines, "Errands"), vim.inspect(lines))
    assert(has_line_with(lines, "  Saturday"), vim.inspect(lines))
    assert(has_line_with(lines, "- Buy milk  (2026-09-17)  p3  @errands"), vim.inspect(lines))
    -- Lower cased: curl normalises the escapes it is handed, and which case
    -- they arrive in is not this plugin's to assert.
    assert(
      has_line_with({ table.concat(double.asked, " "):lower() }, "query=today%20%7c%20overdue"),
      vim.inspect(double.asked)
    )

    -- The task line, found by its text so the assertion does not depend on how
    -- many heading lines came before it.
    local task_line = nil
    for number, line in ipairs(lines) do
      if line:find("Buy milk", 1, true) then
        task_line = number
      end
    end
    assert(task_line, vim.inspect(lines))

    local opened = nil
    local task_buffer = require("todoist.task_buffer")
    local real_open = task_buffer.open
    task_buffer.open = function(id)
      opened = id
    end

    vim.api.nvim_win_set_cursor(0, { task_line, 0 })
    list.open_task_under_cursor()

    task_buffer.open = real_open
    assert(opened == "6XGg", vim.inspect(opened))
  end,

  ["a valid filter matching nothing is an empty view, not a refusal"] = function()
    local double = serve({
      ["/api/v1/tasks/filter"] = { status = 200, body = EMPTY_PAGE },
      ["/api/v1/projects"] = { status = 200, body = EMPTY_PAGE },
      ["/api/v1/sections"] = { status = 200, body = EMPTY_PAGE },
    })
    point_at(double)

    local lines, notifications = open("today")
    double.close()

    assert(has_line_with(lines, "No tasks."), vim.inspect(lines))
    assert(not has_line_with(lines, "refused"), vim.inspect(lines))
    assert(#notifications == 0, vim.inspect(notifications))
  end,

  ["a refused filter shows the API's own message"] = function()
    local double = serve({
      ["/api/v1/tasks/filter"] = { status = 400, body = '{"error":"Invalid query: unexpected token"}' },
      ["/api/v1/projects"] = { status = 200, body = EMPTY_PAGE },
      ["/api/v1/sections"] = { status = 200, body = EMPTY_PAGE },
    })
    point_at(double)

    local lines, notifications = open("broken")
    double.close()

    assert(has_line_with(lines, "The API refused this view:"), vim.inspect(lines))
    assert(has_line_with(lines, "Invalid query: unexpected token"), vim.inspect(lines))
    assert(not has_line_with(lines, "No tasks."), vim.inspect(lines))
    assert(has_line_with(notifications, "Invalid query: unexpected token"), vim.inspect(notifications))
  end,

  ["a slow answer for a view that is no longer shown does not overwrite the one now on screen"] = function()
    local double = serve({
      ["/api/v1/tasks/filter"] = {
        status = 200,
        delay_ms = 150,
        body = '{"results":[{"id":"old","content":"Stale task","project_id":"1"}],"next_cursor":null}',
      },
      ["/api/v1/tasks"] = {
        status = 200,
        body = '{"results":[{"id":"new","content":"Fresh task","project_id":"1"}],"next_cursor":null}',
      },
      ["/api/v1/projects"] = { status = 200, body = '{"results":[{"id":"1","name":"Errands"}],"next_cursor":null}' },
      ["/api/v1/sections"] = { status = 200, body = EMPTY_PAGE },
    })
    point_at(double)

    local buf = todoist.open("today")
    vim.wait(30)
    todoist.open()

    -- Let the fast (all-open) view draw, then let the slow (today) answer,
    -- which is still in flight, land after it.
    assert(vim.wait(2000, function()
      return has_line_with(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "Fresh task")
    end, 5))
    double.close()

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert(has_line_with(lines, "Fresh task"), vim.inspect(lines))
    assert(not has_line_with(lines, "Stale task"), vim.inspect(lines))
  end,
}
