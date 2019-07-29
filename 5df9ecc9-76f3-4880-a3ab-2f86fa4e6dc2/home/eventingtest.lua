local eventing = require('eventing')

local loop = eventing.EventLoop:create()

function sleep(seconds)
  local promise = eventing.Promise:create()
  local timer = eventing.Timer:setTimeout(function()
    promise:resolveDeferred()
  end, seconds)
  loop:attachTimer(timer)
  return promise
end

local yay1 = async(function()
  await(sleep(3))
  print('waited for 3 seconds')
end)

local yay2 = async(function()
  await(sleep(5))
  print('waited for 5 seconds')
end)

loop.signals:addGlobalListener(function(...)
  print(...)
end)

loop.signals:on('interrupted', function()
  loop:stop()
end)

loop:setImmediate(function()
  print('press ctrl+c to exit')
  yay1()
  yay2()
end)

loop:start()
print('done!')