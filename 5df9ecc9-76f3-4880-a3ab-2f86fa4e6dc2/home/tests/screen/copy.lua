-- Test copying regions of a screen
local screen = require("screen")
local image = require("image")

local image = image.loadHDG("/home/tests/screen/boot-logo.hdg")
screen.clear()

image:draw(1, 1)
screen.copy(1, 1, 50, 20, 50, 0)
screen.copy(1, 1, 100, 20, 0, 10)
screen.update(true)
os.sleep(1)

image:unload()