local image = require("image")

frames = {}

for i = 1, 15 do
    frames[#frames + 1] = image.loadHDG("yourname/" .. i .. ".hdg")
end 
for i = 1, 1000 do
    frames[i % 15 + 1]:draw()
    os.sleep(0.3)
end

--error()
require("io").read()