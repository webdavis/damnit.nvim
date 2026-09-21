-- One object as a buffer: what it draws, what :w sends, and where a refusal
-- lands.

local TESTS_DIR = arg[0]:match("(.*)/") or "."

-- `:Dam` is declared by the plugin file rather than by `setup`, so the case
-- that runs the command loads it the way Neovim would.
dofile(TESTS_DIR .. "/../plugin/damnit.lua")

local fake_dam = dofile(TESTS_DIR .. "/helpers/fake_dam.lua")
local queue = require("damnit.queue")
local task_buffer = require("damnit.task_buffer")

local OID = "badb4903b653809e591c31118004e07de7c8183c"

--- dam's own refusal for a dependency that would close a loop, as
--- `CliError::document` writes it. The chain is invented; the shape is not.
local CYCLE = table.concat({
  '{"error": {"kind": "refused", "rule": "cycle", ',
  '"message": "badb490 cannot depend on that: it would form a cycle through a9db854 -> badb490", ',
  '"oids": ["badb4903b653809e591c31118004e07de7c8183c", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77"]}}',
})

---@param run fun(buf: integer, fake: damnit.FakeDam, notifications: string[])
---@param opts { open: fun(oid: string): integer? }?
local function with_task(run, opts)
  local fake = fake_dam.install({ fixtures = TESTS_DIR .. "/fixtures/full" })
  queue.reset()

  local notifications = {}
  local real = vim.notify
  vim.notify = function(text)
    table.insert(notifications, text)
  end

  local open = (opts or {}).open or task_buffer.open
  local buf = open(OID) or vim.api.nvim_get_current_buf()
  fake_dam.settle(function()
    return vim.api.nvim_buf_line_count(buf) > 1
  end)

  local ok, err = pcall(run, buf, fake, notifications)

  vim.notify = real
  vim.cmd("silent! %bwipeout!")
  queue.reset()
  fake_dam.remove(fake)

  assert(ok, err)
end

---@param buf integer
---@param key string
---@param value string
local function set_field(buf, key, value)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^" .. key .. ":") then
      vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { ("%s: %s"):format(key, value) })

      return
    end
  end

  error("no " .. key .. " line in the buffer")
end

--- Write the buffer and hand back the one argv that went out, or nil when none
--- did.
---@param fake damnit.FakeDam
---@return string?
local function written(fake)
  local before = #fake_dam.argv_log(fake)
  vim.cmd("write")

  -- A case expecting no call still waits long enough for one to be logged, so
  -- an accidental call is caught rather than raced past.
  if not pcall(fake_dam.settle, function()
    return #fake_dam.argv_log(fake) > before
  end, 200) then
    return nil
  end

  return fake_dam.argv_log(fake)[before + 1]
end

---@param buf integer
---@return vim.Diagnostic[]
local function diagnostics(buf)
  return vim.diagnostic.get(buf, { namespace = task_buffer.NAMESPACE })
end

return {
  ["reads the object with dam show and draws its frontmatter"] = function()
    with_task(function(buf, fake)
      assert(
        vim.tbl_contains(fake_dam.argv_log(fake), "show " .. OID .. " --json"),
        vim.inspect(fake_dam.argv_log(fake))
      )
      assert(vim.bo[buf].filetype == "damtask", vim.bo[buf].filetype)
      assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "---")
      assert(
        vim.tbl_contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "subject: buy soy milk"),
        vim.inspect(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      )
    end)
  end,

  [":Dam task opens the same buffer the keymap does"] = function()
    with_task(function(buf, fake)
      assert(
        vim.tbl_contains(fake_dam.argv_log(fake), "show " .. OID .. " --json"),
        vim.inspect(fake_dam.argv_log(fake))
      )
      assert(vim.bo[buf].filetype == "damtask", vim.bo[buf].filetype)
    end, {
      open = function(oid)
        vim.cmd("Dam task " .. oid)

        return nil
      end,
    })
  end,

  ["sends only the changed field and marks the buffer unmodified"] = function()
    with_task(function(buf, fake)
      set_field(buf, "subject", "buy the oat milk")

      assert(written(fake) == ("edit %s --subject buy the oat milk --json"):format(OID), "the wrong argv")

      fake_dam.settle(function()
        return vim.bo[buf].modified == false
      end)
      assert(vim.bo[buf].modified == false, "a landed write leaves the buffer unmodified")
    end)
  end,

  ["sends a changed path as the container dam mv takes"] = function()
    with_task(function(buf, fake)
      set_field(buf, "path", "home/inbox/")

      assert(written(fake) == ("mv %s home/ --json"):format(OID), "the wrong argv")
    end)
  end,

  ["sends nothing when nothing changed"] = function()
    with_task(function(buf, fake, notifications)
      assert(written(fake) == nil, "nothing was sent")
      assert(notifications[#notifications] == "damnit.nvim: nothing changed", vim.inspect(notifications))
      assert(vim.bo[buf].modified == false)
    end)
  end,

  ["puts a local refusal on the line it is about, and sends nothing"] = function()
    with_task(function(buf, fake)
      set_field(buf, "priority", "9")

      assert(written(fake) == nil, "a local refusal costs no call")

      local found = diagnostics(buf)
      assert(#found == 1, vim.inspect(found))
      assert(found[1].message:find("1, 2, 3 or 4", 1, true), found[1].message)
      assert(found[1].lnum > 0, "the priority line is not line one")
      assert(vim.bo[buf].modified == true, "the text stays where it can be fixed")
    end)
  end,

  ["puts dam's own refusal on line one and leaves the buffer modified"] = function()
    with_task(function(buf, fake)
      set_field(buf, "depends", "a9db854060d1943ef9eb9f6d7a8ac0b1ace45d77")
      vim.env.DAMNIT_TEST_EXIT = "4"
      vim.env.DAMNIT_TEST_STDERR = CYCLE

      assert(written(fake) ~= nil, "the edit went out")
      fake_dam.settle(function()
        return #diagnostics(buf) > 0
      end)

      local found = diagnostics(buf)
      assert(found[1].message:find("form a cycle", 1, true), found[1].message)
      assert(found[1].lnum == 0, tostring(found[1].lnum))
      assert(vim.bo[buf].modified == true)
    end)
  end,
}
