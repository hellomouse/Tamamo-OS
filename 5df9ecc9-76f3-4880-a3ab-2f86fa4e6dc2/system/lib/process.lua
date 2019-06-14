-- API
local api = {}
local processes = {}
local currentProcess = nil

-- Optimization for lua

-- Create new process
function api.createNewProcess(name, func)
	local pid = #processes + 1
  local process = {}
  
	process.name = name
	process.func = func
	process.pid = pid
  process.status = "created"
  
	if dll.getCurrentProcess() ~= nil then
		proc.parent = dll.getCurrentProcess()
  end
  
	processes[pid] = process
	return process
end

-- Get process by PID
function api.getProcess(PID)

end

-- Get current process
function api.getCurrentProcess()
  return currentProcess
end

-- Kill process
function api.killProcess(PID, forceKill)
end

-- Get all processes
function api.getActiveProcesses()

end

return api