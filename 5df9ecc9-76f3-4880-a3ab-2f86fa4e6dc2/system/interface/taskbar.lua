local GUI = require("gui")
local screen = require("screen")
local eventing = require("eventing")
local system = require("/system/system.lua")
local unicode = require("unicode")

-- colors:
-- 1: orange - 0x944E28
-- 2: l gray - 0x3F433C
-- 3: d gray - 0x2B2E29

-- - home button
-- - open apps button / task manager
-- - <tabs for programs>
-- - minecraft time - display as virtual clock
-- - irl time / date - DONE
-- - battery - DONE
-- - ram usage (maybe vertical bar!) - DONE
-- process counter
-- - shutdown / reboot / logout

-- search computer in dropdown

-- TODO system maybe have array of containers, where only top is processed for events
-- but draw all, container needs to have alpha

-- drop shadow on the things


local container = GUI.createContainer(0, 0, screen.getWidth(), 3, 0)
container.drawObject = function(container)
  screen.setBackground(0x3F433C)
  screen.setForeground(0xFFFFFF)
  screen.drawBrailleRectangle(screen.getWidth() - 12 - 1, 1.5, unicode.len(" 01:00:00 AM "), 2)
  screen.set(screen.getWidth() - 12 - 1, 2, " 01:00:00 AM ")

  screen.setBackground(0x2B2E29)
  screen.drawBrailleRectangle(screen.getWidth() - 12 - 12 - 1, 1.5, 12, 2) -- unicode.len(" 12/02/2019 ")
  screen.set(screen.getWidth() - 12 - 12 - 1, 2, " 12/02/2019 ")

  screen.setBackground(0x944E28)
  local ram = " RAM | "
  local x = screen.getWidth() - 12 - 12 - 1 - unicode.len(ram) - 1
  screen.drawBrailleRectangle(x, 1.5, unicode.len(ram), 2)
  screen.set(x, 2, ram)

  screen.setBackground(0x3F433C)
  x = screen.getWidth() - 12 - 12 - 2 - unicode.len(ram) - unicode.len(" ---- 50% ") - 1
  screen.drawBrailleRectangle(x, 1.5, unicode.len(" ---- 50% "), 2)
  screen.set(x, 2, " ---- 50% ")

  screen.setBackground(0x944E28)
  screen.drawBrailleRectangle(2, 1.5, unicode.len(" Tamamo OS "), 2)
  screen.set(2, 2, " Tamamo OS ")

  local programtitle = " [x]                     Title of your program              V"
  screen.drawBrailleRectangle(14, 1.5, 70, 2)
  screen.set(14, 2, programtitle)
end

-- (x, y, text, textColor, width, height, align)

-- local minecraftTimeLabel = GUI.createLabel(screen.getWidth() - 15, 0, "MC 01:00 AM", 0xDDDDDD, 15, 5, GUI.ALIGN_TOP_LEFT)
-- local IRLTimeLabel = GUI.createLabel(screen.getWidth() - 15, 1, "IRL 01:00 AM", 0xDDDDDD, 15, 5, GUI.ALIGN_TOP_LEFT)
-- local IRLDateLabel = GUI.createLabel(screen.getWidth() - 15, 2, "08/01/2019", 0xDDDDDD, 15, 5, GUI.ALIGN_TOP_LEFT)

-- container:addChild(minecraftTimeLabel)
-- container:addChild(IRLTimeLabel)
-- container:addChild(IRLDateLabel)

local searchInput = GUI.createInput(12, 0, 30, 3, 0x333333, 0xFFFFFF, 0x555555, 0xFFFFFF, 1, 0x888888, "Search computer")
-- container:addChild(searchInput)

local timer = eventing.Timer:setInterval(function()
  require("component").ocemu.log("Called")
  -- screen.setForeground(0x0)
  -- screen.drawText(2, screen.getHeight() - 1, "hello")
  -- screen.update()
end, 1)

-- system.attachTimer(timer)
system.addContainer(container)