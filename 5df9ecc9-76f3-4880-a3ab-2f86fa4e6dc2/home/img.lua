local image = require("image")
local i = image.loadHDG("test.hdg")

local x = os.clock()
i:draw()
--error(string.format("elapsed time: %.2f\n", os.clock() - x))
require("io").read()