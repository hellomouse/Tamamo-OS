local image = require("image")
local screen = require("screen")
local i = image.loadHDG("test.hdg")

local x = os.clock()
local count = 1


for j = 1, count do
    -- screen.fill(1, 1, screen.getWidth(), screen.getHeight(), " ")
    i:draw()
end

screen.setForeground(0)
screen.setBackground(0xFFFFFF)
screen.set(40, 40, string.format("Elapsed time: %.2f", (os.clock() - x) / count ))
screen.set(40, 41, "Hello")

--error()
require("io").read()