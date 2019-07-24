-- Test if screen buffer force update will work
local screen = require("screen")
screen.clear()
screen.setBackground(0xFF0000)
screen.drawBrailleEllipse(20, 20, 10, 5)

-- Draw extra stuff with gpu
local gpu = require("component").gpu
gpu.setBackground(0xFFFFFF)
gpu.fill(1, 1, screen.getWidth(), screen.getHeight(), " ")

-- Force update
screen.update(true)