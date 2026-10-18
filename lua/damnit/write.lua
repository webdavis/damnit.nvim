local M = {}

---@class damnit.QueueEntry
---@field args string[]
---@field label string
---@field on_done fun(data: table?, err: damnit.Failure?)
---@field verb? string
---@field network? boolean
---@field background? boolean
---@field handle? vim.SystemObj
---@field started_at? integer
---@field finished? boolean
---@field cancelled? boolean

function M.submit(app, request)
  local on_error = request.on_error or app.say.report

  app.queue.submit({
    args = request.args,
    label = request.label,
    on_done = function(data, err)
      if err then
        on_error(err)
      elseif request.on_ok then
        request.on_ok(data)
      end

      if request.refresh then
        request.refresh(app)
      end
    end,
  })
end

return M
