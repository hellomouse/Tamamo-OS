local image = require("image")
local screen = require("screen")
local i = image.loadHDG("test.hdg")

screen.clear()
local x = os.clock()

i:draw()

--require("component").ocemu.log(string.format("Elapsed time: %.2f", (os.clock() - x) ))

screen.setForeground(0)
screen.setBackground(0xFFFFFF)
screen.drawText(80, 40, string.format("Elapsed time: %.2f", (os.clock() - x) ))
screen.update(true) -- TODO rewrite system

--error()

require("io").read()
i:unload()