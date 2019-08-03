local coroutine = require("coroutine")

-- API
local api = {
  STATUS_CREATED = 1,
  STATUS_DEAD = 2,
  STATUS_READY = 3,
  STATUS_PAUSED = 4,
  STATUS_RUNNING = 5
}

local processes = {}
local currentProcess = nil
local processCount = 0

-- Optimization for lua
local getn = table.getn
local create = coroutine.create
local status = coroutine.status
local resume = coroutine.resume

-- Create new process
function api.createNewProcess(name, func)
  local pid
  
  -- Avoid adding new array elements and
  -- wasting RAM as array automatically preallocates memory
  -- which cannot be undone
  if processCount ~= #processes then
    for i = 1, #processes do
      if process[i] == nil then
        pid = i
        goto end
      end
    end
  else
    -- Create new index
    pid = #processes + 1
  end
  ::end::

  local process = {}
  
	process.name = name
	process.co = create(func)
	process.pid = pid
  process.status = api.STATUS_CREATED
  process.parent = currentProcess
  process.errorHandler = nil
  process.safeKillHandler = nil

  processCount = processCount + 1
	processes[pid] = process
	return process
end

-- Main process loop
function api.processLoop()
  local errored, errorMsg
  while true do
    os.sleep(0.05) -- Force yield TODO check if needed
    for i = 1, #processes do
      if processes[i] == nil then goto continue end
      currentProcess = processes[i]

      -- Skip paused coroutines
      if currentProcess.status == api.STATUS_PAUSED then goto continue end

      -- Check for dead coroutines
      if currentProcess.status == api.STATUS_DEAD or status(currentProcess.co) == "dead" then
        api.kill(currentProcess.pid, true)
        goto continue
      end

      -- Try running the current process
      currentProcess.status = api.STATUS_RUNNING
      errored, errorMsg = resume(currentProcess.co)
      
      if errored then
        -- If there is an error handler to it call it
        -- If current thread has no parent then just error()
        if currentProcess.errorHandler then
          currentProcess.errorHandler(errorMsg)
        elseif currentProcess.parent == nil then
          error(errorMsg)
        end

        api.kill(currentProcess.pid, true)
      else
        -- Set status to "READY" and do nothing
        currentProcess.status = api.STATUS_READY
      end
  
      ::continue::
    end
  end
end

-- Get process by PID
function api.getProcess(pid)
  return processes[pid]
end

-- Get current process
function api.getCurrentProcess()
  return currentProcess
end

-- Kill process
function api.killProcess(pid, forceKill)
  if not forceKill then
    -- Killing current process is bad
    if processes[pid] == currentProcess and currentProcess.status ~= api.STATUS_DEAD then
      error("Cannot kill currently running process")
    end

    -- Don't kill if safe kill handler if exists and it refuses to kill
    if processes[pid].safeKillHandler and not processes[pid].safeKillHandler() then
      return
    end
  end

  processes[pid].status = api.STATUS_DEAD
  processes[pid] = nil
  processCount = processCount - 1
end

-- Get all processes
function api.getActiveProcesses()
  return processes
end

-- Process count
function api.getProcessCount()
  return processCount
end



return api