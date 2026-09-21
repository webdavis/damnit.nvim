-- Reading one finished dam process: the exit code, the signal, and the error
-- document dam writes on standard error under --json.

local answer = require("damnit.answer")

return {
  ["refuses a rule and an oid list that are not the shapes dam sends"] = function()
    local document = vim.json.encode({
      error = { kind = "refused", rule = 7, message = "98d8780 cannot be completed:", oids = "a9db854" },
    })
    local _, err = answer.interpret({ code = 4, stdout = "", stderr = document }, "done 98d8780")

    assert(err.kind == "refused", err.kind)
    assert(err.rule == nil, vim.inspect(err.rule))
    assert(err.oids == nil, vim.inspect(err.oids))
  end,

  ["drops an oid list holding something that is not an oid"] = function()
    local document = vim.json.encode({
      error = { kind = "refused", rule = "blocked", message = "98d8780 cannot be completed:", oids = { "a9db854", 7 } },
    })
    local _, err = answer.interpret({ code = 4, stdout = "", stderr = document }, "done 98d8780")

    assert(err.rule == "blocked", vim.inspect(err.rule))
    assert(err.oids == nil, "half an oid list names the wrong blockers")
  end,

  ["says what a document said when it carried no message of its own"] = function()
    local document = vim.json.encode({ error = { kind = "refused", rule = "blocked", message = "", oids = {} } })
    local _, err = answer.interpret({ code = 4, stdout = "", stderr = document }, "done 98d8780")

    assert(err.message == "done 98d8780 failed with exit 4: dam said blocked and nothing more", err.message)
    assert(err.plugin == true, "the plugin wrote this one")
    assert(err.rule == "blocked", vim.inspect(err.rule))
  end,

  ["falls back to the kind when a message-less document named no rule"] = function()
    local document = vim.json.encode({ error = { kind = "store", message = "", oids = {} } })
    local _, err = answer.interpret({ code = 1, stdout = "", stderr = document }, "status")

    assert(err.kind == "store", err.kind)
    assert(err.message == "status failed with exit 1: dam said store and nothing more", err.message)
  end,

  ["reads a call a signal killed as cancelled, whichever signal it was"] = function()
    for name, signal in pairs({ sigint = 2, sigterm = 15, sigkill = 9 }) do
      local _, err = answer.interpret({ code = 0, signal = signal, stdout = "", stderr = "" }, "push todoist")

      assert(err ~= nil and err.kind == "cancelled", name .. ": " .. vim.inspect(err))
      assert(err.code == 3, name .. ": " .. tostring(err.code))
    end
  end,

  ["says who was stopped when the signal left no message behind"] = function()
    local _, err = answer.interpret({ code = 0, signal = 9, stdout = "", stderr = "" }, "push todoist")

    assert(err.message == "push todoist was stopped", err.message)
    assert(err.plugin == true, "the plugin wrote this one")
  end,

  ["keeps dam's own word for the cancellation when it managed to write one"] = function()
    local out = { code = 0, signal = 2, stdout = "", stderr = "dam: cancelled" }
    local _, err = answer.interpret(out, "push todoist")

    assert(err.message == "cancelled", err.message)
    assert(err.plugin == nil, "dam wrote this message, so it takes no prefix")
  end,

  ["keeps the timeout on its own path, signal and all"] = function()
    local _, err = answer.interpret({ code = 124, signal = 15, stdout = "", stderr = "" }, "push todoist")

    assert(err.kind == "timeout", vim.inspect(err))
    assert(err.code == 124, tostring(err.code))
    assert(err.message:find("took longer than", 1, true), err.message)
  end,
}
