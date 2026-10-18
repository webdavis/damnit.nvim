local M = {}

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
