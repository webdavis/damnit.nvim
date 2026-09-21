-- The completed buffer against a loopback double.
--
-- The real curl runs against a server this spec starts on 127.0.0.1, so the
-- window on the query string, the cursor that pages within it, the reopen and
-- every answer are real. No token and no network: the double answers, and the
-- token is a string made up here.
--
-- Each route holds a sequence of answers, the last one repeating, so a case can
-- say what the second and third reads of the same endpoint bring back.

local completed = require("damnit.completed")
local todoist = require("damnit")

local SECRET = "0123456789abcdef0123456789abcdef01234567"

local COMPLETED_PATH = "/api/v1/tasks/completed/by_completion_date"

local EMPTY_PAGE = '{"items":[],"next_cursor":null}'

--- An HTTP server on a port the operating system picks, answering each request
--- from the sequence its path names.
---@param routes table<string, { status: integer, body: string }[]>
---@return table double
local function serve(routes)
  local server = assert(vim.uv.new_tcp())
  local double = { asked = {}, answered = 0, served = {} }

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

      local path = target:match("^[^?]*")
      local answers = routes[path]
      local route = { status = 404, body = '{"error":"no such route"}' }
      if answers then
        double.served[path] = (double.served[path] or 0) + 1
        route = answers[math.min(double.served[path], #answers)]
      end

      local head = {
        ("HTTP/1.1 %d Whatever"):format(route.status),
        "Content-Type: application/json",
        ("Content-Length: %d"):format(#route.body),
        "Connection: close",
      }

      socket:write(table.concat(head, "\r\n") .. "\r\n\r\n" .. route.body, function()
        double.answered = double.answered + 1
        socket:read_stop()
        socket:close()
      end)
    end)
  end)

  double.port = server:getsockname().port

  --- How many times one path was asked for.
  ---@param path string
  ---@return integer
  double.count = function(path)
    return double.served[path] or 0
  end

  double.close = function()
    vim.wait(2000, function()
      return double.answered == #double.asked
    end, 5)

    server:close()
  end

  return double
end

---@param double table
local function point_at(double)
  vim.env.TODOIST_SPEC_TOKEN = SECRET
  todoist.options = {
    token_command = nil,
    token_env = "TODOIST_SPEC_TOKEN",
    base_url = ("http://127.0.0.1:%d/api/v1"):format(double.port),
    curl = "curl",
    timeout = 5,
    views = {},
    sidebar = { side = "left", width = 40, view = "today" },
  }
  todoist.setup({})
end

---@param buf integer
---@return string[]
local function lines_of(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

--- Wait until the buffer stops saying it is reading.
---@param buf integer
local function settle(buf)
  assert(
    vim.wait(5000, function()
      local lines = lines_of(buf)
      return lines[#lines] ~= "Reading completed tasks..."
    end, 5),
    vim.inspect(lines_of(buf))
  )
end

--- Open the completed history and wait for its first screen.
---@return integer buf
---@return string[] notifications raised while it loaded
local function open()
  local notifications = {}
  local real_notify = vim.notify
  vim.notify = function(message)
    table.insert(notifications, message)
  end

  local buf = completed.open()
  settle(buf)
  vim.notify = real_notify

  return buf, notifications
end

---@param lines string[]
---@param needle string
---@return boolean
local function has_line_with(lines, needle)
  for _, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return true
    end
  end

  return false
end

--- The line number a task's text sits on.
---@param buf integer
---@param needle string
---@return integer?
local function line_of(buf, needle)
  for number, line in ipairs(lines_of(buf)) do
    if line:find(needle, 1, true) then
      return number
    end
  end
end

---@param body string
---@return table
local function ok(body)
  return { status = 200, body = body }
end

local NEWEST =
  '{"items":[{"id":"1","content":"newest","completed_at":"2026-09-17T08:00:00Z"}],"next_cursor":"page-two"}'
local OLDER = '{"items":[{"id":"2","content":"older","completed_at":"2026-09-02T08:00:00Z"}],"next_cursor":null}'

return {
  ["the first screen is one page, and the window it asked for is today's"] = function()
    local double = serve({ [COMPLETED_PATH] = { ok(NEWEST) } })
    point_at(double)

    local buf = open()
    double.close()

    local lines = lines_of(buf)
    assert(has_line_with(lines, "Todoist: completed"), vim.inspect(lines))
    assert(has_line_with(lines, "2026-09-17  newest"), vim.inspect(lines))
    assert(has_line_with(lines, "1 completed tasks."), vim.inspect(lines))
    assert(double.count(COMPLETED_PATH) == 1, "the first screen read more than one page")

    local asked = double.asked[1]
    assert(asked:find("since=", 1, true), asked)
    assert(asked:find("until=", 1, true), asked)
    assert(asked:find("limit=50", 1, true), asked)
    assert(not asked:find("cursor=", 1, true), asked)
  end,

  ["the bottom of the list asks for the next page exactly once"] = function()
    local double = serve({ [COMPLETED_PATH] = { ok(NEWEST), ok(OLDER) } })
    point_at(double)

    local buf = open()
    assert(double.count(COMPLETED_PATH) == 1, double.count(COMPLETED_PATH))

    -- On the last task line, which is what a `j` off the bottom reaches.
    vim.api.nvim_win_set_cursor(0, { assert(line_of(buf, "newest")), 0 })
    completed.load_more()
    settle(buf)

    assert(has_line_with(lines_of(buf), "2026-09-02  older"), vim.inspect(lines_of(buf)))
    assert(double.count(COMPLETED_PATH) == 2, double.count(COMPLETED_PATH))
    assert(double.asked[2]:find("cursor=page-two", 1, true), double.asked[2])

    -- The walk still has windows left, so what stops the next two moves is the
    -- cursor being above the last task rather than the walk being done.
    assert(not has_line_with(lines_of(buf), "as far as the API goes"), vim.inspect(lines_of(buf)))

    vim.api.nvim_win_set_cursor(0, { assert(line_of(buf, "newest")), 0 })
    completed.load_more()
    completed.load_more()

    -- A load says it is reading before it spawns anything, so the footer still
    -- being the count proves no page was asked for, with nothing to wait on.
    local after = lines_of(buf)
    assert(
      after[#after]:find("2 completed tasks.", 1, true),
      "a move above the last line asked for a page: " .. after[#after]
    )

    double.close()
    assert(
      double.count(COMPLETED_PATH) == 2,
      "a cursor that is not on the last line asked for another page: " .. double.count(COMPLETED_PATH)
    )
  end,

  ["an empty window is walked through to the one that holds a task"] = function()
    local double = serve({
      [COMPLETED_PATH] = { ok(EMPTY_PAGE), ok(EMPTY_PAGE), ok(OLDER) },
    })
    point_at(double)

    local buf = open()
    double.close()

    assert(has_line_with(lines_of(buf), "2026-09-02  older"), vim.inspect(lines_of(buf)))
    assert(double.count(COMPLETED_PATH) == 3, double.count(COMPLETED_PATH))

    -- Three different windows, each stepping back from the one before it.
    local windows = {}
    for _, target in ipairs(double.asked) do
      windows[target:match("since=[^&]*")] = true
    end
    assert(vim.tbl_count(windows) == 3, vim.inspect(double.asked))
  end,

  ["a history with nothing in it says how far back the API was read"] = function()
    local double = serve({ [COMPLETED_PATH] = { ok(EMPTY_PAGE) } })
    point_at(double)

    local buf = open()
    local walked = double.count(COMPLETED_PATH)

    -- The walk reached its floor, so nothing below asks for more.
    vim.api.nvim_win_set_cursor(0, { #lines_of(buf), 0 })
    completed.load_more()
    double.close()

    local lines = lines_of(buf)
    assert(has_line_with(lines, "No completed tasks."), vim.inspect(lines))
    assert(has_line_with(lines, "which is as far as the API goes"), vim.inspect(lines))
    assert(walked == 12, "the walk did not read every window: " .. walked)
    assert(double.count(COMPLETED_PATH) == walked, "a walk at its floor asked for another page")
  end,

  ["u reopens the task and its line leaves the buffer"] = function()
    local double = serve({
      [COMPLETED_PATH] = {
        ok(
          '{"items":[{"id":"1","content":"newest","completed_at":"2026-09-17T08:00:00Z"},'
            .. '{"id":"2","content":"older","completed_at":"2026-09-16T08:00:00Z"}],"next_cursor":null}'
        ),
      },
      ["/api/v1/tasks/1/reopen"] = { ok("{}") },
    })
    point_at(double)

    local buf = open()

    local notifications = {}
    local real_notify = vim.notify
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    vim.api.nvim_win_set_cursor(0, { assert(line_of(buf, "newest")), 0 })
    completed.reopen_under_cursor()

    assert(
      vim.wait(5000, function()
        return not has_line_with(lines_of(buf), "newest")
      end, 5),
      vim.inspect(lines_of(buf))
    )
    vim.notify = real_notify
    double.close()

    local lines = lines_of(buf)
    assert(has_line_with(lines, "2026-09-16  older"), vim.inspect(lines))
    assert(has_line_with(lines, "1 completed tasks."), vim.inspect(lines))
    assert(has_line_with(notifications, "reopened"), vim.inspect(notifications))
    assert(double.count("/api/v1/tasks/1/reopen") == 1, double.count("/api/v1/tasks/1/reopen"))
  end,

  ["a refused reopen keeps every line and reports the API's own message"] = function()
    local double = serve({
      [COMPLETED_PATH] = { ok(OLDER) },
      ["/api/v1/tasks/2/reopen"] = {
        { status = 400, body = '{"error":"Invalid argument value"}' },
      },
    })
    point_at(double)

    local buf = open()

    local notifications = {}
    local real_notify = vim.notify
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    vim.api.nvim_win_set_cursor(0, { assert(line_of(buf, "older")), 0 })
    completed.reopen_under_cursor()

    assert(
      vim.wait(5000, function()
        return #notifications > 0
      end, 5),
      "the refusal was never reported"
    )
    vim.notify = real_notify
    double.close()

    assert(has_line_with(notifications, "Invalid argument value"), vim.inspect(notifications))
    assert(has_line_with(lines_of(buf), "2026-09-02  older"), vim.inspect(lines_of(buf)))
    assert(has_line_with(lines_of(buf), "1 completed tasks."), vim.inspect(lines_of(buf)))
  end,

  ["u on a line holding no task says so and asks the API for nothing"] = function()
    local double = serve({ [COMPLETED_PATH] = { ok(OLDER) } })
    point_at(double)

    local buf = open()

    local notifications = {}
    local real_notify = vim.notify
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    completed.reopen_under_cursor()

    vim.notify = real_notify
    double.close()

    assert(has_line_with(notifications, "no task on this line"), vim.inspect(notifications))
    assert(double.count(COMPLETED_PATH) == 1, double.count(COMPLETED_PATH))
    assert(has_line_with(lines_of(buf), "2026-09-02  older"), vim.inspect(lines_of(buf)))
  end,
}
