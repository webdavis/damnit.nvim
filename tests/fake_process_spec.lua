local fake_process = require("helpers.fake_process")

local function queue()
  return require("damnit").app().queue
end

return {
  ["drain ends on its own while an answer is held, so a failing spec ends too"] = function()
    local fake = fake_process.install()
    fake.hold = true
    queue().submit({ args = { "status", "--json" }, label = "status" })

    local rescued = false
    local rescue = vim.uv.new_timer()
    rescue:start(
      500,
      0,
      vim.schedule_wrap(function()
        rescued = true
        fake.release()
      end)
    )

    fake_process.drain()

    rescue:stop()
    rescue:close()
    fake_process.remove(fake)

    assert(not rescued, "drain waited for a held answer that nobody released")
    assert(fake.delivered == 2, "the handshake and the held call were answered: " .. fake.delivered)
    assert(#fake.held == 0, "an answer is still held")
  end,
}
