-- Main interface

local thread = require("thread")

thread.create(function()
  local screen = require("screen")
  local computer = require("computer")

  local freePercent

  --while true do
    screen.setBackground(0x333333)
    screen.setForeground(0xFFFFFF)
    screen.fillRect(1, 1, screen.getWidth(), 1)

    -- In game time (Padding 2 to right)
    screen.drawText(screen.getWidth() - 21, 1, os.date("%x %I:%M:%S %p"))

    -- Power left in computer
    screen.drawText(screen.getWidth() - 33, 1, "━━━━ 100%")

    -- RAM usage (Padding 4 to left)
    freePercent = (1 - computer.freeMemory() / computer.totalMemory())

    screen.drawText(screen.getWidth() - 57, 1,
      "RAM           " .. math.ceil(100 * freePercent) .. "% Used")
    screen.setForeground(0x777777)
    screen.set(screen.getWidth() - 52, 1, "━━━━━━━━", false, true)
    screen.setForeground(0xFF0000)
    screen.set(screen.getWidth() - 52, 1, string.rep("━", 7 - math.floor(freePercent * 7)), false, true)


    -- Concept: tabs
    screen.setForeground(0xFFFFFF)
    screen.setBackground(0x000000)
    screen.fillRect(1, 2, screen.getWidth(), 3)
    screen.setBackground(0x444444)
    screen.fillRect(1, 2, 24, 3)
    screen.drawText(3, 3, "Hello world       X")

    screen.setBackground(0x222222)
    screen.setForeground(0xAAAAAA)
    screen.fillRect(25, 2, 24, 3)
    screen.drawText(26, 3, " Hello world       X")

    screen.update()

    os.sleep(1)
  --end
end)