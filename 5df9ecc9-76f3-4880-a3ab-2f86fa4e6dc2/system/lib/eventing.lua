local computer = require('computer')
local LinkedList = require('linkedlist')

local Promise = {}
Promise.__index = Promise

function Promise:create(fn)
    local obj = setmetatable({
        complete = false,
        resolved = false,
        rejected = false,
        value = nil,
        resolveCallbacks = {},
        rejectCallbacks = {}
    }, Promise)
    if fn then
        local ok, err = pcall(
            fn,
            function(...) obj:resolveDeferred(...) end,
            function(err) obj:rejectDeferred(err) end
        )
        if not ok then obj:rejectDeferred(err) end
    end
    return obj
end

function Promise.resolve(...)
    return setmetatable({
        complete = true,
        resolved = true,
        rejected = false,
        value = table.pack(...),
        resolveCallbacks = {},
        rejectCallbacks = {}
    }, Promise)
end

function Promise.reject(err)
    return setmetatable({
        complete = true,
        resolved = false,
        rejected = true,
        value = err,
        resolveCallbacks = {},
        rejectCallbacks = {}
    }, Promise)
end

function Promise:resolveDeferred(...)
    if self.complete then return end
    self.complete = true
    self.resolved = true
    self.value = table.pack(...)
    for _, fn in ipairs(self.resolveCallbacks) do
        fn()
    end
end

function Promise:rejectDeferred(err)
    if self.complete then return end
    self.complete = true
    self.rejected = true
    self.value = err
    for _, fn in ipairs(self.rejectCallbacks) do
        fn()
    end
end

function Promise:done(fn)
    local after = Promise:create()
    local callback = function()
        local out = table.pack(pcall(fn, table.unpack(self.value)))
        if out[1] then
            if getmetatable(out[2]) == Promise then
                -- it's a promise, chain it
                out[2]:done(function(...) after:resolveDeferred(...) end)
                out[2]:catch(function(err) after:rejectDeferred(err) end)
            else
                -- return directly
                after:resolveDeferred(table.unpack(out, 2))
            end
        else
            after:rejectDeferred(out[2])
        end
    end
    if self.complete then
        if self.resolved then callback() end
    else
        local resolveCallbacks = self.resolveCallbacks
        resolveCallbacks[#resolveCallbacks + 1] = callback
    end
    return after
end

-- this is literally the .done method but with rejectCallbacks instead
function Promise:catch(fn)
    local after = Promise:create()
    local callback = function()
        local out = table.pack(pcall(fn, self.value))
        if out[1] then
            if getmetatable(out[2]) == Promise then
                -- it's a promise, chain it
                out[2]:done(function(...) after:resolveDeferred(...) end)
                out[2]:catch(function(err) after:rejectDeferred(err) end)
            else
                -- return directly
                after:resolveDeferred(table.unpack(out, 2))
            end
        else
            after:rejectDeferred(out[2])
        end
    end
    if self.complete then
        if self.rejected then callback() end
    else
        local rejectCallbacks = self.rejectCallbacks
        rejectCallbacks[#rejectCallbacks + 1] = callback
    end
    return after
end

local EventEmitter = {}
EventEmitter.__index = EventEmitter

function EventEmitter:create()
    local obj = setmetatable({
        -- list of callbacks by event name
        _events = {},
        -- functions to call for every event
        globalListeners = {}
    }, EventEmitter);
    return obj
end

function EventEmitter:on(event, fn)
    local listeners = self._events[event]
    if listeners then
        listeners[#listeners + 1] = fn
    else
        self._events[event] = {fn}
    end
end

function EventEmitter:emit(event, ...)
    for _, fn in ipairs(self.globalListeners) do
        fn(event, ...)
    end
    local listeners = self._events[event]
    if not listeners then return end
    for _, fn in ipairs(listeners) do
        fn(...)
    end
end

function EventEmitter:removeListener(event, listener)
    local listeners = self._events[event]
    if not listeners then return false end
    for i, fn in ipairs(listeners) do
        if fn == listener then
            table.remove(listeners, i)
            return true
        end
    end
    return false
end

function EventEmitter:removeAllListeners(event)
    if not event then
        self._events = {}
    else
        self._events[event] = nil
    end
end

function EventEmitter:addGlobalListener(fn)
    local listeners = self.globalListeners
    listeners[#listeners + 1] = fn
end

function EventEmitter:removeGlobalListener(fn)
    local listeners = self.globalListeners
    for i, fn2 in ipairs(listeners) do
        if fn == fn2 then
            table.remove(listeners, i)
            return
        end
    end
end


local Timer = {}
Timer.__index = Timer

function Timer:create()
    local obj = setmetatable({
        -- the event loop of which the timer has been attached to
        loop = nil,
        -- if the timer is repeating, the interval
        interval = nil,
        -- next expire time of the timer
        expire = nil,
        -- function to call on timer expire
        callback = nil
    }, Timer)
    return obj
end

function Timer:setTimeout(fn, timeout)
    local obj = Timer:create()
    obj.callback = fn
    obj.expire = computer.uptime() + timeout
    return obj
end

function Timer:setInterval(fn, interval)
    local obj = Timer:create()
    obj.callback = fn
    obj.expire = computer.uptime() + interval
    obj.interval = interval
    return obj
end

local EventLoop = {}
EventLoop.__index = EventLoop

function EventLoop:create(timing)
    local obj = setmetatable({
        -- sorted linkedlist of registered timers
        timers = LinkedList:create(),
        -- list of immediate callbacks to be run on the next turn of the loop
        immediate = {},
        -- list of polling callbacks, will be run every turn until unregistered
        -- meant to be used to poll for other events
        polling = {},
        -- list of coroutines bound to the event loop
        -- will be resumed every event loop tick until they end
        coroutines = {},
        -- fires off signals as events when they are received
        signals = EventEmitter:create(),
        -- whether or not the event loop should keep running
        run = true
    }, EventLoop)
    return obj
end

function EventLoop:attachTimer(timer)
    local timers = self.timers
    local position = timers.first
    local timerExpire = timer.expire
    while position and position.expire < timerExpire do
        position = position._llnext
    end
    timers:insertBefore(position, timer)
end

function EventLoop:detachTimer(timer)
    self.timers:remove(timer)
end

function EventLoop:setImmediate(fn)
    local immediate = self.immediate
    immediate[#immediate + 1] = fn
end

function EventLoop:addCoroutine(co)
    local coroutines = self.coroutines
    coroutines[#coroutines + 1] = co
end

function EventLoop:addPollingFunction(fn)
    local polling = self.polling
    polling[#polling + 1] = fn
end

function EventLoop:removePollingFunction(fn)
    local polling = self.polling
    for i, fn2 in ipairs(polling) do
        if fn == fn2 then
            table.remove(polling, i)
            return
        end
    end
end

function EventLoop:stop()
    self.run = false
end

function EventLoop:start()
    self.run = true
    while self.run do
        -- step 1: timers
        local time = computer.uptime()
        local timers = self.timers
        local position = timers.first
        while position and position.expire <= time do
            local timer = position
            position = position._llnext
            timers:remove(timer)
            timer.callback()
            if timer.interval then
                timer.expire = time + timer.interval
                self:attachTimer(timer)
            end
        end
        -- step 2: immediate
        local immediate = self.immediate
        self.immediate = {}
        for _, fn in ipairs(immediate) do
            fn()
        end
        -- step 3: bound coroutines
        local coroutines = self.coroutines
        for i, co in ipairs(coroutines) do
            local ok = coroutine.resume(co)
            if not ok then
                table.remove(coroutines, i)
            end
        end
        -- step 4: polling
        -- poll for signals
        while true do
            local signal = table.pack(computer.pullSignal(0))
            if signal.n == 0 then break end
            self.signals:emit(table.unpack(signal))
        end
        -- custom polling functions
        for _, fn in ipairs(self.polling) do fn() end
    end
end

function async(fn)
    return function(...)
        local args = table.pack(...)
        local promise = Promise:create()
        local co = coroutine.create(function()
            local out = table.pack(pcall(fn, table.unpack(args)))
            if out[1] then
                promise:resolveDeferred(table.unpack(out, 2))
            else
                promise:rejectDeferred(out[2])
            end
        end)
        coroutine.resume(co)
        return promise
    end
end

function await(promise)
    local co = coroutine.running()
    if not co then error('await can only be called in an async function') end
    local result = nil
    promise:done(function(...)
        result = table.pack(true, ...)
        if coroutine.status(co) == 'suspended' then
            coroutine.resume(co, table.unpack(result))
        end
    end)
    promise:catch(function(err)
        result = table.pack(false, err)
        if coroutine.status(co) == 'suspended' then
            coroutine.resume(co, table.unpack(result))
        end
    end)
    if not result then return coroutine.yield()
    else return table.unpack(result) end
end

local api = {
    EventEmitter = EventEmitter,
    Promise = Promise,
    EventLoop = EventLoop,
    Timer = Timer,
    async = async,
    await = await
}
return api
