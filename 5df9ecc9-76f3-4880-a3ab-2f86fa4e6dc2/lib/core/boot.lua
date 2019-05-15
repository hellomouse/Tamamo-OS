-- called from /init.lua
local raw_loadfile = ...

_G._OSVERSION = "Tamamo OS 1.0.0"

local component = component
local computer = computer
local unicode = unicode

-- Runlevel information.
local runlevel, shutdown = "S", computer.shutdown

computer.runlevel = function() return runlevel end
computer.shutdown = function(reboot)
  runlevel = reboot and 6 or 0
  if os.sleep then
    computer.pushSignal("shutdown")
    os.sleep(0.1) -- Allow shutdown processing.
  end
  shutdown(reboot)
end

-- Look for screen component
local screen = component.list('screen', true)()
for address in component.list('screen', true) do
  if #component.invoke(address, 'getKeyboards') > 0 then
    screen = address
    break
  end
end

-- Set boot screen if possible
_G.boot_screen = screen







-- Report boot progress if possible.
local gpu = component.list("gpu", true)()
local w, h
if gpu and screen then
  -- Bind gpu
  gpu = component.proxy(gpu)
  gpu.bind(screen)

  -- Fill screen entirely white
  -- The set bg and fg calls are required
  w, h = gpu.maxResolution()
  gpu.setResolution(w, h)
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")
end

-- Functions to help display status
local progressw = w * 3 / 4
local mid = w / 2

local fill = gpu.fill
local setForeground = gpu.setForeground
local setBackground = gpu.setBackground
local set = gpu.set

-- Display a status message (Optionally at a y value)
-- This message will be centered
local function status(msg, y)
  if not gpu or not screen then return end

  y = y or h * 3 / 4 - 1
  if gpu and screen then
    setBackground(0x000000)
    setForeground(0xFFFFFF)
    fill(1, y, w, 1, " ")
    set(math.floor(mid - string.len(msg) / 2), y, msg)
  end
end

-- Display a centered orange progress bar filled up to percent
local function progressbar(percent)
  if not gpu or not screen then return end

  local bg = setBackground(0x000000)
  local fg = setForeground(0xF48042)

  fill((w - progressw) / 2, h * 3 / 4 - 5, progressw * percent, 1, "▂")
  setForeground(0x333333)
  fill((w - progressw) / 2 + progressw * percent, h*3/4 - 5, progressw * (1 - percent) - 1, 1, "▂")
  setBackground(bg)
  setForeground(fg)
end






-- Begin BOOT sequence --
status(_OSVERSION .. " - Press ALT for advanced boot options", h*3/4 - 2)
status("Booting " .. _OSVERSION .. "...")
progressbar(0.1)

-- Custom low-level dofile implementation reading from our ROM.
local loadfile = function(file)
  status("Loading " .. file)
  return raw_loadfile(file)
end

local function dofile(file)
  local program, reason = loadfile(file)
  if program then
    local result = table.pack(pcall(program))
    if result[1] then
      return table.unpack(result, 2, result.n)
    else error(result[2]) end
  else error(reason) end
end

-- After loading this you can require() modules
status("Initializing package management...")
progressbar(0.2)

-- Load file system related libraries we need to load other stuff moree
-- comfortably. This is basically wrapper stuff for the file streams
-- provided by the filesystem components.
local package = dofile("/lib/package.lua")

do
  -- Unclutter global namespace now that we have the package module and a filesystem
  _G.component = nil
  _G.computer = nil
  _G.process = nil
  _G.unicode = nil

  -- Inject the package modules into the global namespace, as in Lua.
  _G.package = package

  -- Initialize the package module with some of our own APIs.
  package.loaded.component = component
  package.loaded.computer = computer
  package.loaded.unicode = unicode
  package.loaded.buffer = assert(loadfile("/lib/buffer.lua"))()
  package.loaded.filesystem = assert(loadfile("/lib/filesystem.lua"))()

  -- Inject the io modules
  _G.io = assert(loadfile("/lib/io.lua"))()
end

status("Initializing file system...")
progressbar(0.3)

-- Mount the ROM and temporary file systems to allow working on the file
-- system module from this point on.
require("filesystem").mount(computer.getBootAddress(), "/")
progressbar(0.5)

status("Running boot scripts...")
progressbar(0.6)

-- Run library startup scripts. These mostly initialize event handlers.
local function rom_invoke(method, ...)
  return component.invoke(computer.getBootAddress(), method, ...)
end

local scripts = {}
for _, file in ipairs(rom_invoke("list", "/system/boot")) do
  local path = "/system/boot/" .. file
  if not rom_invoke("isDirectory", path) then
    table.insert(scripts, path)
  end
end

-- Scripts should have a number in front for sort order
table.sort(scripts)
for i = 1, #scripts do
  dofile(scripts[i])
end

-- Draw boot screen logo --
if gpu and screen then
  local image = require("image")
  local i = image.loadHDG("/system/assets/boot-logo.hdg")

  -- We want image above the loading screen and centered
  i:draw(mid - i.width / 2, h * 3 / 4 - 8 - i.height)
end

-- Load connected components --
status("Initializing components...")
progressbar(0.8)

for c, t in component.list() do
  computer.pushSignal("component_added", c, t)
end

status("Initializing system...")
progressbar(1.0)

computer.pushSignal("init") -- so libs know components are initialized.
require("event").pull(1, "init") -- Allow init processing.
_G.runlevel = 1
