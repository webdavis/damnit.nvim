-- The task buffer against a loopback double: that `:Todoist task <id>` renders
-- one, that `:w` sends what changed and clears the modified flag, and that a
-- refused write leaves the buffer modified and reports the API's own message.
--
-- The double is a server this spec starts on 127.0.0.1 and the token is a string
-- made up here, so the real curl and the real `:write` path run and no network
-- and no token are involved.

local todoist = require("todoist")

-- `--clean -l` sources no plugin directory, so the command this spec drives is
-- loaded the way Neovim would load it, out of the file that declares it.
dofile(((arg[0]:match("(.*)/") or ".") .. "/../plugin/todoist.lua"))

local SECRET = "0123456789abcdef0123456789abcdef01234567"

local TASK = {
  id = "6XGgmFVcrG5RRjVr",
  content = "Buy oat milk",
  description = "The kind in the grey carton.",
  due = { string = "tomorrow 9am" },
  priority = 3,
  labels = { "errands" },
  project_id = "2203306141",
  section_id = vim.NIL,
}

--- A server answering one queued response per request.
---@param answers table[] each `{ status = integer, body = string }`
---@return integer port
---@return string[] requests filled in as they arrive
local function serve(answers)
  local server = assert(vim.uv.new_tcp())
  local requests = {}

  server:bind("127.0.0.1", 0)
  server:listen(8, function()
    local socket = assert(vim.uv.new_tcp())
    server:accept(socket)

    local request = ""
    socket:read_start(function(err, chunk)
      assert(not err, err)
      if not chunk then
        return
      end

      request = request .. chunk
      local length = tonumber(request:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")) or 0
      local head, body = request:match("^(.-)\r\n\r\n(.*)$")
      if not head or #body < length then
        return
      end

      requests[#requests + 1] = request

      local answer = answers[#requests] or { status = 500, body = "{}" }
      local response = ("HTTP/1.1 %d Whatever\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s"):format(
        answer.status,
        #answer.body,
        answer.body
      )

      socket:write(response, function()
        socket:read_stop()
        socket:close()
      end)
    end)
  end)

  return server:getsockname().port, requests
end

--- Point the plugin at the double.
---@param port integer
local function configure(port)
  vim.env.TODOIST_SPEC_TOKEN = SECRET
  todoist.options = {
    token_command = nil,
    token_env = "TODOIST_SPEC_TOKEN",
    base_url = ("http://127.0.0.1:%d/api/v1"):format(port),
    curl = "curl",
    timeout = 5,
  }
  todoist.setup({})
end

---@param condition fun(): boolean
local function until_true(condition)
  assert(vim.wait(5000, condition, 5), "the request never answered")
end

--- Collect every notification raised while `run` executes. `run` is handed the
--- list as it fills, so a case can wait for the one it is about.
---@param run fun(collected: string[])
---@return string[]
local function notifications(run)
  local collected = {}
  local real = vim.notify

  vim.notify = function(message)
    collected[#collected + 1] = message
  end

  local ok, err = pcall(run, collected)
  vim.notify = real
  assert(ok, err)

  return collected
end

--- Open the double's task and make its buffer current.
---@return integer buf
local function opened()
  local before = vim.api.nvim_get_current_buf()

  vim.cmd("Todoist task " .. TASK.id)
  until_true(function()
    return vim.api.nvim_get_current_buf() ~= before
  end)

  return vim.api.nvim_get_current_buf()
end

--- Wipe the buffer so the next case starts from a window holding nothing.
---@param buf integer
local function forget(buf)
  vim.bo[buf].modified = false
  vim.cmd(("silent! %dbwipeout!"):format(buf))
end

return {
  ["opens one task through :Todoist task <id> in a fresh editor"] = function()
    local port, requests = serve({ { status = 200, body = vim.json.encode(TASK) } })
    configure(port)

    local buf = opened()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    assert(vim.bo[buf].buftype == "acwrite", vim.bo[buf].buftype)
    assert(vim.bo[buf].filetype == "markdown", vim.bo[buf].filetype)
    assert(vim.bo[buf].modified == false, "a freshly opened task reads as unwritten")
    assert(lines[2] == "content: Buy oat milk", vim.inspect(lines))
    assert(lines[7] == "section:", vim.inspect(lines))
    assert(lines[9] == "The kind in the grey carton.", vim.inspect(lines))
    assert(requests[1]:find("GET /api/v1/tasks/" .. TASK.id .. " ", 1, true), requests[1])

    forget(buf)
  end,

  ["writes the changed fields and clears the modified flag"] = function()
    local written = vim.tbl_extend("force", TASK, { content = "Buy oat milk and bread" })
    local port, requests = serve({
      { status = 200, body = vim.json.encode(TASK) },
      { status = 200, body = vim.json.encode(written) },
    })
    configure(port)

    local buf = opened()
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "content: Buy oat milk and bread" })
    assert(vim.bo[buf].modified, "an edited buffer should read as modified")

    local said = notifications(function()
      vim.cmd("write")
      until_true(function()
        return not vim.bo[buf].modified
      end)
    end)

    assert(requests[2]:find("POST /api/v1/tasks/" .. TASK.id .. " ", 1, true), requests[2])
    assert(requests[2]:find('"content":"Buy oat milk and bread"', 1, true), requests[2])
    assert(not requests[2]:find("due_string", 1, true), "an unchanged due string was sent")
    assert(#said == 1 and said[1]:find("saved", 1, true), vim.inspect(said))

    forget(buf)
  end,

  ["reports the API's own message on a rejected write and stays modified"] = function()
    local port = serve({
      { status = 200, body = vim.json.encode(TASK) },
      { status = 400, body = '{"error":"Due date is invalid"}' },
    })
    configure(port)

    local buf = opened()
    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "due: the 30th of Febuary" })

    local said = notifications(function(collected)
      vim.cmd("write")
      until_true(function()
        return #collected > 0
      end)
    end)

    assert(#said == 1 and said[1]:find("Due date is invalid", 1, true), vim.inspect(said))
    assert(vim.bo[buf].modified, "a rejected write left the buffer reading as written")

    forget(buf)
  end,

  ["refuses a hand-edited header locally and says which line"] = function()
    local port, requests = serve({ { status = 200, body = vim.json.encode(TASK) } })
    configure(port)

    local buf = opened()
    vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "priority: urgent" })

    local said = notifications(function()
      vim.cmd("write")
    end)

    assert(#requests == 1, "a buffer that does not parse was sent anyway")
    assert(#said == 1 and said[1]:find("priority", 1, true), vim.inspect(said))
    assert(vim.bo[buf].modified, "a refused write left the buffer reading as written")

    forget(buf)
  end,

  ["writes nothing when nothing changed"] = function()
    local port, requests = serve({ { status = 200, body = vim.json.encode(TASK) } })
    configure(port)

    local buf = opened()
    vim.bo[buf].modified = true

    local said = notifications(function()
      vim.cmd("write")
    end)

    assert(#requests == 1, "an unchanged task was written back")
    assert(#said == 1 and said[1]:find("nothing changed", 1, true), vim.inspect(said))
    assert(not vim.bo[buf].modified, "an unchanged buffer stayed modified")

    forget(buf)
  end,

  ["refuses anything but `task <id>`"] = function()
    local said = notifications(function()
      vim.cmd("Todoist")
      vim.cmd("Todoist today")
      vim.cmd("Todoist task 1 2")
    end)

    assert(#said == 3, vim.inspect(said))
    for _, message in ipairs(said) do
      assert(message:find("usage is :Todoist task <id>", 1, true), message)
    end
  end,
}
